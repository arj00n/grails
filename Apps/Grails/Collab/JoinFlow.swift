import AppKit
import GrailsKit
import SwiftUI

/// An invite link whose library isn't on this Mac: what it looks like, and the way through.
@MainActor @Observable
final class JoinState {
    let link: GrailsLink
    let name: String
    var diagnosis: JoinDiagnosis
    /// This Mac's Google accounts, for the access request ("add me, ben@studio.com").
    var emails: [String]
    var checking = false
    @ObservationIgnored var continuation: CheckedContinuation<Bool, Never>?

    init(link: GrailsLink, name: String, diagnosis: JoinDiagnosis, emails: [String]) {
        self.link = link; self.name = name; self.diagnosis = diagnosis; self.emails = emails
    }

    var copy: JoinDiagnosis.Copy { diagnosis.copy(library: name, hint: link.hint) }

    /// What the teammate sends the owner: which library, what they need, and the address to add.
    var request: InviteText.Message {
        let page = URL(string: AppModel.defaultLinkPage)!
        return InviteText.accessRequest(library: name, hint: link.hint, myEmails: emails, link: link.webURL(page: page))
    }

    func resolve(_ ok: Bool) {
        continuation?.resume(returning: ok)
        continuation = nil
    }
}

extension AppModel {
    /// Opening a link to a library this Mac doesn't have: look for it in every synced folder first (no questions when it's there), and
    /// otherwise say what it looks like and what to do. Replaces the bare folder picker; `locateLibrary` stays as the way out.
    func findOrExplain(_ link: GrailsLink) async -> Bool {
        await collab.findOrExplain(link, name: link.name ?? workspaces.first { $0.id == link.library }?.name)
    }
}

extension CollabModel {
    /// What this Mac has, and the library if it is anywhere a sync client shows.
    func joinFacts(for link: GrailsLink) async -> JoinFacts {
        let home = home
        let installed = driveAppInstalled()
        return await Task.detached(priority: .userInitiated) {
            let accounts = CloudPlaces.driveAccounts(home: home)
            let others = CloudPlaces.otherRoots(home: home)
            let found = LibraryFinder.find(id: link.library, accounts: accounts, otherRoots: others.map(\.root.url), hint: link.hint)
            return JoinFacts(driveAppInstalled: installed, accounts: accounts, otherServices: others.map(\.service), found: found)
        }.value
    }

    func findOrExplain(_ link: GrailsLink, name: String?) async -> Bool {
        guard let app else { return false }
        let facts = await joinFacts(for: link)
        accounts = facts.accounts
        let diagnosis = JoinDiagnosis.diagnose(hint: link.hint, facts: facts)
        if case .found(let url) = diagnosis { return await open(url, for: link) }
        join?.resolve(false)
        let state = JoinState(link: link, name: name ?? "this library", diagnosis: diagnosis, emails: facts.accounts.filter { $0.state == .ready }.map(\.email))
        join = state
        guard sheet.present(JoinProblemView(model: app, state: state)) else {
            // no window to show it on: the old way, a folder picker
            join = nil
            return await app.locateLibrary(id: link.library, name: name)
        }
        startJoinWatch(state)
        return await withCheckedContinuation { state.continuation = $0 }
    }

    private func open(_ url: URL, for link: GrailsLink) async -> Bool {
        guard let app else { return false }
        await app.openOrCreate(at: url, remember: remember)
        recordPresence()
        return app.libraryID == link.library
    }

    /// Looks again every 5 s while the screen is up, so signing in to Drive or being added to the Shared drive is enough.
    private func startJoinWatch(_ state: JoinState) {
        Task { [weak self] in
            while let self, self.join === state {
                try? await Task.sleep(for: .seconds(5))
                guard self.join === state else { return }
                await self.recheck(state)
            }
        }
    }

    func recheck(_ state: JoinState) async {
        guard !state.checking else { return }
        state.checking = true
        let facts = await joinFacts(for: state.link)
        state.checking = false
        accounts = facts.accounts
        state.emails = facts.accounts.filter { $0.state == .ready }.map(\.email)
        let d = JoinDiagnosis.diagnose(hint: state.link.hint, facts: facts)
        if case .found(let url) = d {
            closeJoin(state)
            state.resolve(await open(url, for: state.link))
        } else {
            state.diagnosis = d
        }
    }

    func closeJoin(_ state: JoinState, resolving: Bool? = nil) {
        if join === state { join = nil; sheet.dismiss() }
        if let resolving { state.resolve(resolving) }
    }

    func perform(_ action: JoinAction, _ state: JoinState) {
        switch action {
        case .installDrive: opener(DriveWeb.download)
        case .openDriveApp:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.drivefs") { opener(url) } else { opener(DriveWeb.download) }
        case .openPrivacySettings: opener(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
        case .openSharedWithMe:
            let account = accounts.first { $0.state == .ready && $0.domain == state.link.hint?.domain }?.email ?? accounts.first { $0.state == .ready }?.email
            opener(DriveWeb.sharedWithMe(account: account))
        case .askForAccess: copyRequest(state)
        case .checkAgain: Task { await recheck(state) }
        case .locate:
            closeJoin(state)
            Task {
                let ok = await app?.locateLibrary(id: state.link.library, name: state.name) ?? false
                if ok { recordPresence() }
                state.resolve(ok)
            }
        }
    }

    /// The request goes on the clipboard as well as into the share sheet, so it can be pasted into whichever chat the invite came from.
    func copyRequest(_ state: JoinState) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.request.body, forType: .string)
        app?.showToast("Request copied")
    }
}
