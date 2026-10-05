import AppKit
import StashKit

/// Receives `stash://` links and `.stash` folders opened from outside the app (Finder, Slack, a browser).
final class StashAppDelegate: NSObject, NSApplicationDelegate {
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
    // MARK: Making links

    private func copyToPasteboard(_ url: URL, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast(toast)
    }

    /// A link to a library, collection, tag or item that opens on any Mac that has this library.
    func copyLink(_ target: StashLink.Target, canvas: Bool = false) {
        guard !libraryID.isEmpty else { return }
        copyToPasteboard(StashLink(library: libraryID, name: libraryName, target: target, canvas: canvas).url, toast: "Link copied")
    }

    /// For someone who hasn't added this library yet: opening it asks them to pick the shared folder.
    func copyInviteLink() {
        guard !libraryID.isEmpty else { return }
        copyToPasteboard(StashLink(library: libraryID, name: libraryName).url, toast: "Invite link copied")
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
            } else if let link = StashLink(url: url) {
                Task { await openLink(link) }
            }
        }
    }

    func promptJoinWithLink() {
        prompt = PromptRequest(title: "Join with Link", placeholder: "stash://open?…", confirmTitle: "Join") { [weak self] text in
            guard let self else { return }
            guard let link = StashLink(text: text) else { self.errorMessage = "That isn't a Stash link."; return }
            Task { await self.openLink(link) }
        }
    }

    func openLink(_ link: StashLink) async {
        // a link can arrive while the app is still opening its library
        for _ in 0..<50 where store == nil && !needsLibrary { try? await Task.sleep(for: .milliseconds(100)) }
        if link.library != libraryID {
            if let w = workspaces.first(where: { $0.id == link.library }), w.exists {
                await openOrCreate(at: w.url)
            } else {
                guard await locateLibrary(id: link.library, name: link.name ?? workspaces.first { $0.id == link.library }?.name) else { return }
            }
        }
        navigate(to: link)
    }

    func switchWorkspace(_ w: Workspace) {
        if w.exists { openLibrary(at: w.url); return }
        Task { _ = await locateLibrary(id: w.id, name: w.name) }
    }

    /// Asks where a library lives on this Mac (a synced shared drive, usually) and opens it if it's the right one.
    private func locateLibrary(id: String, name: String?) async -> Bool {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.treatsFilePackagesAsDirectories = false
        p.message = name.map { "Choose the folder for “\($0)” (it ends in .stash)" } ?? "Choose the library folder (it ends in .stash)"
        p.prompt = "Open"
        guard p.runModal() == .OK, let url = p.url else { return false }
        guard let found = Self.libraryID(at: url) else { errorMessage = "“\(url.lastPathComponent)” isn't a Stash library."; return false }
        guard found == id else { errorMessage = "“\(url.lastPathComponent)” is a different library from the one this link is for."; return false }
        await openOrCreate(at: url)
        return libraryID == id
    }

    private static func libraryID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("library.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["id"] as? String
    }

    private func navigate(to link: StashLink) {
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
