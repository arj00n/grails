import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Team libraries: the set-up flow, the invite checklist, and the screen a teammate sees when an invite's library can't be found. Grails
/// has no server and never signs in to Google: everything here reads what the sync client shows on this Mac and opens Drive's own pages.
@MainActor @Observable
final class CollabModel {
    weak var app: AppModel?

    // What this Mac has. Injectable for the demo (a fake home folder) and set from the real Mac otherwise.
    @ObservationIgnored var home = FileManager.default.homeDirectoryForCurrentUser
    @ObservationIgnored var driveAppInstalled: () -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.drivefs") != nil }
    @ObservationIgnored var attributeReader: DriveItemID.Reader = DriveItemID.systemReader
    /// Opens web pages, apps and mail; the demo records instead.
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var defaults: UserDefaults = .standard
    /// Dev demos don't add to the person's workspace list.
    @ObservationIgnored var remember = true
    @ObservationIgnored var now: () -> Date = Date.init

    struct OtherRoot: Identifiable, Equatable { var service: CloudService; var url: URL; var id: String { url.path } }

    var accounts: [DriveAccount] = []
    private(set) var others: [OtherRoot] = []
    /// Libraries already sitting in each place (folder path → libraries), so set-up offers to use one rather than make a second.
    private(set) var existing: [String: [FoundLibrary]] = [:]
    private(set) var scanned = false

    init(app: AppModel) { self.app = app }

    func scan() async {
        let home = home
        let (a, o, e) = await Task.detached(priority: .userInitiated) { () -> ([DriveAccount], [OtherRoot], [String: [FoundLibrary]]) in
            let a = CloudPlaces.driveAccounts(home: home)
            let o = CloudPlaces.otherRoots(home: home).map { OtherRoot(service: $0.service, url: $0.root.url) }
            var e: [String: [FoundLibrary]] = [:]
            var places = a.flatMap { $0.sharedDrives.map(\.url) + ($0.myDrive.map { [$0] } ?? []) } + o.map(\.url)
            places = Array(places.prefix(24))
            for p in places {
                let found = CloudPlaces.libraries(in: p)
                if !found.isEmpty { e[p.path] = found }
            }
            return (a, o, e)
        }.value
        accounts = a
        others = o
        existing = e
        scanned = true
        // a choice that's gone (Drive signed out meanwhile) falls back to the best one left
        let valid: Bool
        switch service {
        case .google(let email)?: valid = a.contains { $0.email == email && $0.state == .ready }
        case .other(let path)?: valid = o.contains { $0.url.path == path }
        case nil: valid = false
        }
        if !valid { service = defaultService }
    }

    // MARK: Set-up

    enum ServiceChoice: Hashable { case google(String), other(String) }
    enum FolderChoice: Hashable { case sharedDrive(String), myDrive(String), root(String), existing(String) }

    var flow = CollabSetupFlow(step: .service)
    var service: ServiceChoice?
    var folder: FolderChoice?
    var libraryName = "Team Library"
    private(set) var busy = false
    private(set) var problem: String?
    var report: PlacementReport?
    @ObservationIgnored private var checkingSince: Date?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    /// Drive (or Finder) was opened from the Share step.
    private(set) var openedShare = false
    @ObservationIgnored private(set) var setupActive = false

    /// Starts the flow (if it isn't already showing): at Check for a library already in a synced folder, at the beginning otherwise.
    func beginSetup() {
        guard !setupActive else { return }
        setupActive = true
        problem = nil
        openedShare = false
        let placement = currentPlacement
        flow = CollabSetupFlow(current: app?.store == nil ? nil : placement)
        if let name = app?.libraryName, app?.store != nil, placement?.isSynced == true { libraryName = name }
        Task {
            await scan()
            if flow.step == .check { await check() }
        }
    }

    func endSetup() {
        setupActive = false
        checkTask?.cancel()
    }

    /// `~/…` against the home folder in use (the demo's is fake).
    func tilde(_ url: URL) -> String {
        let h = home.path
        return url.path.hasPrefix(h + "/") ? "~" + url.path.dropFirst(h.count) : url.path
    }

    /// Where a library is, in the sync app's own words: "arjun@studio.com · Shared drives ▸ Design".
    func placeLine(_ url: URL) -> String {
        let p = Placement.of(url, home: home)
        guard let rel = p.relativePath, p.isSynced else { return tilde(url.deletingLastPathComponent()) }
        let folders = rel.split(separator: "/").dropLast().joined(separator: " ▸ ")
        let base = p.account ?? p.service?.label ?? ""
        return folders.isEmpty ? base : "\(base) · \(folders)"
    }

    var currentPlacement: Placement? { app?.layout.map { Placement.of($0.root, home: home) } }

    var chosenAccount: DriveAccount? {
        if case .google(let email) = service { return accounts.first { $0.email == email } }
        return nil
    }

    var chosenOther: OtherRoot? {
        if case .other(let path) = service { return others.first { $0.url.path == path } }
        return nil
    }

    var defaultService: ServiceChoice? {
        if let a = CloudPlaces.preferred(accounts) { return .google(a.email) }
        return others.first.map { .other($0.url.path) }
    }

    func chooseService() {
        guard service != nil else { return }
        folder = defaultFolder
        flow.send(.choseService)
    }

    var defaultFolder: FolderChoice? {
        if let a = chosenAccount {
            if let d = a.sharedDrives.first { return existing[d.url.path]?.first.map { .existing($0.url.path) } ?? .sharedDrive(d.url.path) }
            return a.myDrive.map { .myDrive($0.path) }
        }
        return chosenOther.map { .root($0.url.path) }
    }

    /// Where the library goes for the folder choice (or the library itself, for one that's already there).
    var targetURL: URL? {
        let name = libraryName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        switch folder {
        case .sharedDrive(let p)?, .myDrive(let p)?, .root(let p)?:
            return name.isEmpty ? nil : URL(fileURLWithPath: p, isDirectory: true).appendingPathComponent(name + ".grails", isDirectory: true)
        case .existing(let p)?: return URL(fileURLWithPath: p, isDirectory: true)
        case nil: return nil
        }
    }

    /// Makes the library in the chosen folder (or opens the one already there) and moves on to Check.
    func createLibrary() async {
        guard let app, let url = targetURL, !busy else { return }
        busy = true
        problem = nil
        defer { busy = false }
        let fm = FileManager.default
        let isLibrary = fm.fileExists(atPath: url.appendingPathComponent("library.json").path)
        if !isLibrary, fm.fileExists(atPath: url.path) { problem = "That name is taken here"; return }
        await app.openOrCreate(at: url, remember: remember)
        guard app.store != nil, app.layout?.root.standardizedFileURL.path == url.standardizedFileURL.path else { problem = "Couldn't make the library there"; return }
        recordPresence()
        flow.send(.libraryReady)
        await check()
    }

    /// Reads where the open library sits and what the sync client says about it; while Drive is still taking it, looks again every 2 s.
    func check() async {
        guard let layout = app?.layout else { return }
        if checkingSince == nil { checkingSince = now() }
        let facts = await Task.detached { [reader = attributeReader] in FileFacts.read(library: layout.root, reader: reader) }.value
        let waitedLong = now().timeIntervalSince(checkingSince ?? now()) > 45
        report = PlacementReport(placement: Placement.of(layout.root, home: home), facts: facts, accounts: accounts, waitedLong: waitedLong)
        folderID = facts.driveItemID
        checkTask?.cancel()
        if report?.waiting == true, flow.step == .check {
            checkTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self?.check()
            }
        }
    }

    func continueFromCheck() {
        guard let report else { return }
        checkTask?.cancel()
        flow.send(.checked(canContinue: report.canContinue))
    }

    func changeFolder() {
        checkTask?.cancel()
        checkingSince = nil
        if service == nil { service = defaultService }
        folder = defaultFolder
        if flow.step == .check { flow.send(.changeFolder) }
    }

    // MARK: Share

    /// Drive's id of the open library's folder, once Drive has it.
    private(set) var folderID: String?

    /// The page where the owner shares: the Shared drive's own page (Manage members is there), or the library folder's page in My Drive.
    var sharePage: URL? {
        guard let layout = app?.layout else { return nil }
        let p = Placement.of(layout.root, home: home)
        guard p.service == .googleDrive else { return nil }
        if case .sharedDrive(let name) = p.kind, let a = accounts.first(where: { $0.email == p.account }), let d = a.sharedDrives.first(where: { $0.name == name }),
           let id = DriveItemID.read(d.url, reader: attributeReader) {
            return DriveWeb.folder(id: id, account: p.account)
        }
        return DriveWeb.page(for: p, folderID: folderID ?? DriveItemID.read(layout.root, reader: attributeReader))
    }

    func openShare() {
        if let page = sharePage { opener(page) }
        else if let root = app?.layout?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
        openedShare = true
    }

    func openDriveForNewSharedDrive() { opener(DriveWeb.sharedDrives(account: chosenAccount?.email)) }

    // MARK: Invites

    private(set) var invites = InviteList(libraryID: "")
    private(set) var seen: [SeenPerson] = []
    var draft = ""

    var roster: InviteList.Roster { invites.roster(seen: seen, ownHandle: app?.userHandle ?? "") }

    func loadInvites() {
        guard let id = app?.libraryID, !id.isEmpty else { return }
        if invites.libraryID != id { invites = InviteStore.load(libraryID: id, defaults: defaults) }
    }

    private func save() { InviteStore.save(invites, defaults: defaults) }

    func addDraft() {
        loadInvites()
        invites.add(draft, now: now())
        draft = ""
        save()
    }

    func remove(_ id: String) { invites.remove(id); save() }
    func link(_ id: String, handle: String?, unlinking: String? = nil) { invites.link(id, handle: handle, unlinking: unlinking); save() }

    /// Who has turned up: presence records in the library and everyone who has added something.
    func refreshSeen() async {
        loadInvites()
        guard let app, let layout = app.layout else { return }
        let members = await Task.detached { Members.all(in: layout) }.value
        seen = SeenPerson.merge(members: members, contributors: app.contributors)
    }

    /// The owner opened the library: note it, so teammates' Invite screens show who's in.
    func recordPresence() {
        guard let app, let layout = app.layout, ProcessInfo.processInfo.environment["GRAILS_LIBRARY"] == nil || !remember else { return }
        let handle = app.userHandle
        let now = now()
        Task.detached { try? Members.record(handle: handle, in: layout, now: now) }
    }

    var hint: LibraryHint? { currentPlacement.flatMap(LibraryHint.init(placement:)) }

    var inviteLink: URL? {
        guard let app, !app.libraryID.isEmpty else { return nil }
        let typed = (UserDefaults.standard.string(forKey: "linkPage") ?? "").trimmingCharacters(in: .whitespaces)
        guard let page = URL(string: typed.isEmpty ? AppModel.defaultLinkPage : typed) else { return nil }
        return InviteText.link(libraryID: app.libraryID, name: app.libraryName, hint: hint, page: page)
    }

    func message(to contact: String? = nil) -> InviteText.Message? {
        guard let app, let link = inviteLink else { return nil }
        return InviteText.invite(library: app.libraryName, link: link, hint: hint, from: app.userHandle, to: contact)
    }

    /// Teammates with an email address who haven't been sent an invite yet.
    var pendingEmails: [Teammate] { invites.teammates.filter { $0.invitedAt == nil && $0.email != nil } }
    var pending: [Teammate] { invites.teammates.filter { $0.invitedAt == nil } }

    /// One email to everyone not yet invited (Mail, or whichever app handles mailto), then they're marked Invited.
    func emailInvites(_ people: [Teammate]? = nil) {
        let list = people ?? pendingEmails
        let emails = list.compactMap(\.email)
        guard !emails.isEmpty, let m = message(to: list.count == 1 ? list[0].contact : nil), let url = InviteText.mailto(to: emails, message: m) else { return }
        opener(url)
        markInvited(list)
    }

    func copyMessage(for people: [Teammate]? = nil) {
        let list = people ?? pending
        guard let m = message(to: list.count == 1 ? list[0].contact : nil) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m.body, forType: .string)
        markInvited(list)
        app?.showToast("Invite copied")
    }

    func copyLink() {
        guard let link = inviteLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        app?.showToast("Invite link copied")
    }

    func markInvited(_ people: [Teammate]) {
        invites.markInvited(people.map(\.id), at: now())
        save()
    }

    // MARK: Presenting

    @ObservationIgnored let sheet = CollabSheet()

    /// Settings ▸ Library and the sidebar menu: the set-up flow as a sheet on the main window.
    func presentSetup() {
        guard let app else { return }
        sheet.present(CollabSetupView(model: app, onDone: { [weak self] in self?.sheet.dismiss() }))
    }

    func presentInvite() {
        guard let app else { return }
        sheet.present(InviteView(model: app, onClose: { [weak self] in self?.sheet.dismiss() }))
    }

    // MARK: Joining (the invitee's side)

    /// The "can't find this library" screen, while it's up.
    var join: JoinState?
}
