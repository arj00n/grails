import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Dev only (GRAILS_COLLAB_DEMO=<dir>): walks team set-up, invites and every "can't find this library" case against fake home folders
/// (Google Drive for desktop with a work and a personal account, a Shared drive, Drive ids written as real extended attributes), paints
/// each screen to a PNG in light and dark, and writes `result.txt`. Nothing is opened, mailed or copied: links are recorded instead,
/// and the person's own preferences, clipboard and Drive are left alone.
extension AppModel {
    func startCollabDemo(_ dir: String) async {
        needsLibrary = true
        let root = URL(fileURLWithPath: dir)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "xyz.arjoon.grails.collab-demo"
        UserDefaults().removePersistentDomain(forName: suiteName)
        let c = collab
        c.defaults = UserDefaults(suiteName: suiteName)!
        c.remember = false
        c.driveAppInstalled = { true }
        Task { @MainActor in await CollabDemo(app: self, root: root).run() }
    }
}

@MainActor
final class CollabDemo {
    let app: AppModel
    let root: URL
    var log: [String] = []
    var failed = false
    var opened: [URL] = []
    var made: [String] = []

    init(app: AppModel, root: URL) { self.app = app; self.root = root }

    private var c: CollabModel { app.collab }

    func say(_ s: String) { log.append(s); try? log.joined(separator: "\n").write(to: root.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8) }
    func check(_ ok: Bool, _ what: String) { say((ok ? "ok   " : "FAIL ") + what); if !ok { failed = true } }

    /// A fake home folder: `accounts` maps an email to its Shared drives (nil = signed out, its folder left empty).
    func home(_ name: String, accounts: [(String, [String]?)], dropbox: Bool = false) -> URL {
        let h = root.appendingPathComponent("homes/\(name)")
        let fm = FileManager.default
        for (email, drives) in accounts {
            let a = h.appendingPathComponent("Library/CloudStorage/GoogleDrive-\(email)")
            try? fm.createDirectory(at: a, withIntermediateDirectories: true)
            guard let drives else { continue }
            try? fm.createDirectory(at: a.appendingPathComponent("My Drive"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: a.appendingPathComponent("Shared drives"), withIntermediateDirectories: true)
            for d in drives {
                let u = a.appendingPathComponent("Shared drives/\(d)")
                try? fm.createDirectory(at: u, withIntermediateDirectories: true)
                setDriveID(u, "0A" + String(repeating: String(d.prefix(1)), count: 4) + "kTgXyZUk9PVA")
            }
        }
        if dropbox { try? fm.createDirectory(at: h.appendingPathComponent("Library/CloudStorage/Dropbox"), withIntermediateDirectories: true) }
        try? fm.createDirectory(at: h, withIntermediateDirectories: true)
        return h
    }

    /// What Drive for desktop does once it has a folder: its Drive id as an extended attribute.
    func setDriveID(_ url: URL, _ id: String) {
        _ = id.withCString { v in setxattr(url.path, "com.google.drivefs.item-id#S", v, strlen(v), 0, 0) }
    }

    func run() async {
        c.opener = { [weak self] in self?.opened.append($0) }
        let size = CollabSetupView.size

        // 1. Where: a work account with two Shared drives, a personal account, Dropbox
        let owner = home("owner", accounts: [("arjun@studio.com", ["Design", "Marketing"]), ("arjun.v@gmail.com", [])], dropbox: true)
        c.home = owner
        c.beginSetup()
        for _ in 0..<50 where !c.scanned || c.accounts.contains(where: { $0.state == .checking }) { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(200))
        check(c.accounts.map(\.email) == ["arjun@studio.com", "arjun.v@gmail.com"], "both Google accounts found, work first: \(c.accounts.map(\.email))")
        check(c.accounts.first?.sharedDrives.map(\.name) == ["Design", "Marketing"], "the work account's Shared drives are listed")
        check(c.flow.step == .service && c.service == .google("arjun@studio.com"), "starts at Where with the work Drive picked")
        snap(setup, "setup-1-where", size)

        // no Drive on this Mac at all
        c.home = home("bare", accounts: [])
        c.driveAppInstalled = { false }
        await c.scan()
        snap(setup, "setup-1-no-drive", size)
        c.driveAppInstalled = { true }
        c.home = owner
        await c.scan()

        // 2. Folder: Shared drives first; a work account with none gets the two clicks to make one
        c.chooseService()
        check(c.flow.step == .place && c.folder == .sharedDrive(owner.appendingPathComponent("Library/CloudStorage/GoogleDrive-arjun@studio.com/Shared drives/Design").path),
              "Folder defaults to the first Shared drive")
        c.libraryName = "Team Inspo"
        snap(setup, "setup-2-folder", size)
        let noDrives = home("no-shared-drives", accounts: [("arjun@studio.com", [])])
        c.home = noDrives
        await c.scan()
        c.service = .google("arjun@studio.com")
        c.folder = c.defaultFolder
        snap(setup, "setup-2-no-shared-drives", size)
        c.openDriveForNewSharedDrive()
        check(opened.last?.absoluteString == "https://drive.google.com/drive/shared-drives?authuser=arjun@studio.com", "Open Drive goes to Shared drives in the work account: \(opened.last?.absoluteString ?? "-")")
        c.home = owner
        await c.scan()
        c.service = .google("arjun@studio.com")
        c.folder = c.defaultFolder

        // 3. Check: just made, Drive hasn't got it yet → waits; then Drive writes the id → all clear
        await c.createLibrary()
        let lib = owner.appendingPathComponent("Library/CloudStorage/GoogleDrive-arjun@studio.com/Shared drives/Design/Team Inspo.grails")
        made.append(app.libraryID)
        check(FileManager.default.fileExists(atPath: lib.appendingPathComponent("library.json").path) && app.libraryName == "Team Inspo", "the library is made in the Shared drive and opened")
        check(c.flow.step == .check && c.report?.waiting == true && c.report?.rows[1].state == .waiting, "Check waits while Drive hasn't taken it: \(c.report?.issues.map(\.title) ?? [])")
        snap(setup, "setup-3-check-waiting", size)
        setDriveID(lib, "1TeamInspoFolderIdAbCdEfGhIjK")
        await c.check()
        check(c.report?.issues.isEmpty == true && c.report?.canContinue == true, "once Drive has its id, nothing is left to fix")
        snap(setup, "setup-3-check-ok", size)
        // the same screen for a library in My Drive of a personal account (warnings, still allowed) and on this Mac only (blocked)
        let keep = c.report
        c.report = PlacementReport(placement: Placement.of(owner.appendingPathComponent("Library/CloudStorage/GoogleDrive-arjun.v@gmail.com/My Drive/Team Inspo.grails"), home: owner),
                                   facts: FileFacts(driveItemID: "1AbCdEfGhIjKlMnOpQrS"), accounts: c.accounts)
        check(c.report?.issues == [.myDrive, .personalAccount("arjun.v@gmail.com")] && c.report?.canContinue == true, "My Drive in a personal account: two warnings, not blocked: \(c.report?.issues ?? [])")
        snap(setup, "setup-3-check-warnings", size)
        c.report = PlacementReport(placement: Placement(kind: .local), facts: FileFacts())
        check(c.report?.canContinue == false, "a library only on this Mac can't go on")
        snap(setup, "setup-3-check-local", size)
        c.report = keep

        // 4. Share: opens the Shared drive's own page (Manage members is there)
        c.continueFromCheck()
        check(c.flow.step == .share, "Continue goes to Share")
        snap(setup, "setup-4-share", size)
        c.openShare()
        let designID = "0ADDDDkTgXyZUk9PVA"
        check(opened.last?.absoluteString == "https://drive.google.com/drive/folders/\(designID)?authuser=arjun@studio.com", "Open Drive opens the Shared drive's page: \(opened.last?.absoluteString ?? "-")")
        snap(setup, "setup-4-share-opened", size)

        // 5. Invite: one message for everyone, to copy or share anywhere
        c.flow.send(.shared)
        let link = c.inviteLink?.absoluteString ?? ""
        check(link == "https://grails.arjoon.xyz/open#lib=\(app.libraryID)&name=Team%20Inspo&k=sd&at=Design&dom=studio.com" || UserDefaults.standard.string(forKey: "linkPage")?.isEmpty == false,
              "invite link: \(link)")
        let msg = c.message?.body ?? ""
        say("---- invite message ----\n\(msg)\n------------------------")
        check(msg.hasPrefix("Hi,\n") && msg.contains("It lives in the Shared drive “Design” in our studio.com Google Drive.") && msg.contains("sign in with your studio.com account") && msg.contains(link),
              "the message says where it lives, which account, and carries the link")
        snap(setup, "setup-5-invite", size)
        NSPasteboard.general.clearContents()
        c.copyMessage()
        check(NSPasteboard.general.string(forType: .string) == msg, "Copy message puts the whole message on the clipboard")

        // 6. Done, and people turning up: Ana opens it (presence record), Cleo adds something
        c.flow.send(.invited)
        check(c.flow.step == .done, "after the message goes out the set-up is done")
        if let layout = app.layout {
            try? Members.record(handle: "analopez", in: layout)
            try? FixtureLibrary.writeRemoteItem(into: layout, name: "Cleo's pick", addedBy: "cleo")
        }
        await app.refreshLibrary(announce: false)
        await c.refreshSeen()
        check(Set(c.seen.map(\.handle)).isSuperset(of: ["analopez", "cleo"]), "people who opened it or added to it show as here: \(c.seen.map(\.handle))")
        snap(setup, "setup-6-done", size)
        snap({ InviteView(model: self.app) }, "invite", InviteView.size)

        // 7. The teammate's side: every reason an invite's library isn't found, worked out from fake Macs
        let hint = c.hint
        check(hint == LibraryHint(kind: .sharedDrive, place: "Design", domain: "studio.com"), "the link carries: Shared drive Design, studio.com")
        let invite = GrailsLink(library: app.libraryID, name: "Team Inspo", hint: hint)
        let cases: [(String, URL, Bool, (JoinDiagnosis) -> Bool)] = [
            ("no-drive", home("ben-no-drive", accounts: []), false, { $0 == .noApp(.googleDrive) }),
            ("signed-out", home("ben-signed-out", accounts: [("ben@studio.com", nil)]), true, { $0 == .notSignedIn }),
            ("wrong-account", home("ben-personal", accounts: [("ben.ito@gmail.com", [])]), true, { if case .wrongAccount("studio.com", ["ben.ito@gmail.com"]) = $0 { true } else { false } }),
            ("not-shared", home("ben-not-shared", accounts: [("ben@studio.com", ["Marketing"])]), true, { $0 == .notShared(signedIn: ["ben@studio.com"]) }),
            ("unreadable", home("ben-unreadable", accounts: [("ben@studio.com", ["Design"])]), true, { $0 == .cannotRead }),
        ]
        let unreadable = cases[4].1.appendingPathComponent("Library/CloudStorage/GoogleDrive-ben@studio.com")
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        for (name, h, installed, expect) in cases {
            c.home = h
            c.driveAppInstalled = { installed }
            let facts = await c.joinFacts(for: invite)
            let d = JoinDiagnosis.diagnose(hint: invite.hint, facts: facts)
            check(expect(d), "invitee \(name): \(d)")
            let state = JoinState(link: invite, name: "Team Inspo", diagnosis: d, emails: facts.accounts.filter { $0.state == .ready }.map(\.email))
            say("     \(name): \(state.copy.title) — \(state.copy.detail) [\(state.copy.primary.label)]")
            snap({ JoinProblemView(model: self.app, state: state) }, "join-\(name)", CGSize(width: JoinProblemView.width, height: 420))
            if name == "not-shared" {
                check(state.request.body.contains("Could you add me (ben@studio.com) to the Shared drive “Design” as a Content manager?"), "Ask for access names the drive and the address to add")
                say("---- access request ----\n\(state.request.body)\n------------------------")
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path)
        // a folder shared from My Drive needs a shortcut first
        let my = JoinState(link: GrailsLink(library: "x", name: "Refs", hint: LibraryHint(kind: .myDrive, domain: "studio.com")), name: "Refs",
                           diagnosis: .notShared(signedIn: ["ben@studio.com"]), emails: ["ben@studio.com"])
        check(my.copy.primary == .openSharedWithMe, "a My Drive folder: first add the shortcut")
        snap({ JoinProblemView(model: self.app, state: my) }, "join-my-drive-shortcut", CGSize(width: JoinProblemView.width, height: 420))
        c.perform(.openSharedWithMe, my)
        // a link from before hints (or through the router page, which passes only the keys it knows)
        let old = JoinState(link: GrailsLink(library: "x", name: "Refs"), name: "Refs", diagnosis: .notShared(signedIn: ["ben@studio.com"]), emails: ["ben@studio.com"])
        snap({ JoinProblemView(model: self.app, state: old) }, "join-no-hint", CGSize(width: JoinProblemView.width, height: 420))

        // and the happy path: Ben's Drive has the Shared drive, so the library is found with no questions
        let ben = home("ben-ok", accounts: [("ben@studio.com", ["Design"])])
        let benLib = ben.appendingPathComponent("Library/CloudStorage/GoogleDrive-ben@studio.com/Shared drives/Design/Team Inspo.grails")
        try? FileManager.default.copyItem(at: lib, to: benLib)
        c.home = ben
        let found = await c.joinFacts(for: invite)
        check(found.found?.standardizedFileURL.path == benLib.standardizedFileURL.path,
              "on a Mac whose Drive has it, the library is found by itself: \(found.found?.path ?? "nil")")

        // nothing left behind in the person's own index folder
        for id in made {
            let index = GrailsPaths.indexURL(libraryId: id).path
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: index + suffix) }
        }
        say(failed ? "FAIL" : "PASS")
        if ProcessInfo.processInfo.environment["GRAILS_COLLAB_DEMO_QUIT"] != nil { NSApp.terminate(nil) }
    }

    private func setup() -> some View { CollabSetupView(model: app, onDone: {}) }

    /// The view as an image, light and dark, on the sheet's own surface.
    private func snap<V: View>(_ make: () -> V, _ name: String, _ size: CGSize) {
        for (scheme, suffix) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let content = make()
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Ink.surface)
                .environment(\.colorScheme, scheme)
                .environment(\.collabStill, true)
            let r = ImageRenderer(content: content)
            r.scale = 2
            guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: root.appendingPathComponent("snap-\(name)-\(suffix).png"))
        }
    }
}
