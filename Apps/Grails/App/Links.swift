import AppKit
import GrailsKit
import GrailsSync
import GrailsEndpoints

/// Receives `grails://` links and `.grails` folders opened from outside the app (Finder, Slack, a browser).
final class GrailsAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var handler: (([URL]) -> Void)?
    @MainActor static var pending: [URL] = []

    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = Self.handler { handler(urls) } else { Self.pending += urls }
    }

    @MainActor static func connect(_ model: AppModel) {
        handler = { [weak model] urls in model?.handleIncoming(urls) }
        if !pending.isEmpty { let urls = pending; pending = []; handler?(urls) }
    }
}

extension AppModel {
    /// The page that opens an invite or collection link in the app (or offers the download): `<site>/open`, or nil when the
    /// build has no site, and links stay `grails://`. Dev override: UserDefaults key `linkPage`. Settings does not show it.
    static var linkPage: URL? {
        let typed = (UserDefaults.standard.string(forKey: "linkPage") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? GrailsEndpoints.linkPage : URL(string: typed)
    }

    // MARK: Making links

    /// Where links point. A chat app can open the https page; without one the link is `grails://`.
    private func copyToPasteboard(_ link: GrailsLink, toast: String) {
        let url = Self.linkPage.map { link.webURL(page: $0) } ?? link.url
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast(toast)
    }

    /// A link to a library, collection, tag or item that opens on any Mac that has this library.
    func copyLink(_ target: GrailsLink.Target, canvas: Bool = false) {
        guard !libraryID.isEmpty else { return }
        copyToPasteboard(GrailsLink(library: libraryID, name: libraryName, target: target, canvas: canvas), toast: "Link copied")
    }

    /// A shared-folder invite. A bucket invite is per person, so this opens that sheet instead of copying `open#lib`.
    func copyInviteLink() {
        guard libraryPlace.copiesFolderInvite, !libraryID.isEmpty else {
            collab.presentInvite()
            return
        }
        copyToPasteboard(GrailsLink(library: libraryID, name: libraryName, hint: collab.hint), toast: "Invite link copied")
    }

    /// A pasted folder link opens the library. A join link stays in the invite sheet.
    func acceptFolderLink(_ text: String) -> Bool {
        guard PastedLibraryLink.classify(text) == .folder else { return false }
        let link = GrailsLink(text: text) ?? text.split(whereSeparator: \.isWhitespace).compactMap { part in
            GrailsLink(text: String(part.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'.,"))))
        }.first
        guard let link else { return false }
        workspaceDraft = nil
        showTeamHome = false
        Task {
            await openLink(link)
            if libraryID == link.library { onboarding?.finish() }
        }
        return true
    }

    /// The link for what's on screen: the open collection or tag, in the same view mode.
    func copyViewLink() {
        switch source {
        case .collection(let id): copyLink(.collection(id), canvas: viewMode == .canvas)
        case .tag(let t): copyLink(.tag(t), canvas: viewMode == .canvas)
        default: copyLink(.library, canvas: viewMode == .canvas)
        }
    }

    // MARK: Opening links

    func handleIncoming(_ urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) { openLibrary(at: url) }
            } else if let join = JoinLink.parse(url) {
                receiveJoin(join)
            } else if let link = GrailsLink(url: url) {
                Task { await openLink(link) }
            }
        }
    }

    /// A bucket invite, including `grails://i/<id>`. Hold it until the library choice exists, then start the join.
    func receiveJoin(_ join: JoinLink) {
        switch FirstRunInvite.disposition(onboardingVisible: onboarding != nil, libraryChoicePending: libraryChoicePending, libraryOpen: store != nil) {
        case .holdUntilLibraryChoice:
            heldLaunchJoin = join
            launchedToJoin = true
        case .start(let closeOnboardingOnSuccess):
            if closeOnboardingOnSuccess { launchedToJoin = true }
            bucket.beginJoin(join)
        }
    }

    func settleLaunchJoin() {
        libraryChoicePending = false
        guard let join = heldLaunchJoin else { return }
        heldLaunchJoin = nil
        receiveJoin(join)
    }

    func openLink(_ link: GrailsLink, fromHello: Bool = false) async {
        // a link can arrive while the app is still opening its library
        for _ in 0..<50 where store == nil && !needsLibrary { try? await Task.sleep(for: .milliseconds(100)) }
        if !fromHello, onboarding?.step == .hello {
            pendingInvite = link
            return
        }
        if link.library != libraryID {
            if let w = workspaces.first(where: { $0.id == link.library }), w.exists {
                await openOrCreate(at: w.url)
            } else {
                // looks in every synced folder, then says why it can't find it (Collab/JoinFlow.swift); the folder picker is its way out
                guard await findOrExplain(link) else {
                    if fromHello { pendingInvite = link }
                    return
                }
            }
        }
        navigate(to: link)
        if fromHello { onboarding?.finish() }
    }

    func switchWorkspace(_ w: Workspace) {
        if w.exists { openLibrary(at: w.url); return }
        Task { _ = await locateLibrary(id: w.id, name: w.name) }
    }

    /// Asks where a library lives on this Mac (a synced shared drive, usually) and opens it if it's the right one.
    func locateLibrary(id: String, name: String?) async -> Bool {
        let p = LibraryPicker.panel(message: name.map { "Choose the folder for “\($0)” (it ends in .grails)" } ?? "Choose the library folder (it ends in .grails)")
        guard p.runModal() == .OK, let chosen = p.url else { return false }
        guard let url = LibraryFinder.picked(chosen, named: name), let found = Self.libraryID(at: url) else {
            errorMessage = "“\(chosen.lastPathComponent)” isn't a Grails library."; return false
        }
        guard found == id else { errorMessage = "“\(url.lastPathComponent)” is a different library from the one this link is for."; return false }
        await openOrCreate(at: url)
        return libraryID == id
    }

    static func libraryID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("library.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["id"] as? String
    }

    private func navigate(to link: GrailsLink) {
        if link.canvas { viewMode = .canvas }
        switch link.target {
        case .library: break
        case .collection(let id):
            if collections.contains(where: { $0.id == id }) { source = .collection(id) } else { showToast("That collection isn't in this library") }
        case .tag(let tag): source = .tag(tag)
        case .item(let id):
            source = .all
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if summary(id) != nil { selection = [id]; openPreview(id) } else { showToast("That item isn't in this library") }
            }
        }
    }
}

