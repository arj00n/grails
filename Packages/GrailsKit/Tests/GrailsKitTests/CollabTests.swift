import Foundation
import Testing
@testable import GrailsKit

/// A fake home folder with Drive for desktop signed in to a work and a personal account, a signed-out account, Dropbox and iCloud.
enum FakeCloud {
    static let work = "Library/CloudStorage/GoogleDrive-ana@studio.com"
    static let personal = "Library/CloudStorage/GoogleDrive-ana.lopez@gmail.com"

    static func home(sharedDrives: [String] = ["Marketing", "Design"], unreadable: Bool = false) throws -> URL {
        let home = TestSupport.tempDir("cloud")
        let fm = FileManager.default
        var dirs = ["\(work)/My Drive/Inspo", "\(work)/Other computers/My MacBook", "\(personal)/My Drive",
                    "Library/CloudStorage/GoogleDrive-old@studio.com", "Library/CloudStorage/Dropbox/Studio",
                    "Library/Mobile Documents/com~apple~CloudDocs"]
        dirs += sharedDrives.map { "\(work)/Shared drives/\($0)" }
        if sharedDrives.isEmpty { dirs.append("\(work)/Shared drives") }
        for d in dirs { try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true) }
        if unreadable { try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.appendingPathComponent(work).path) }
        return home
    }

    static func makeLibrary(_ path: String, in home: URL, id: String, name: String) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(#"{"id":"\#(id)","name":"\#(name)","schema":1,"createdAt":"2026-01-01T00:00:00.000Z"}"#.utf8).write(to: url.appendingPathComponent("library.json"))
        return url
    }
}

@Suite struct DriveAccountTests {
    @Test func findsEveryGoogleAccountWorkFirstWithItsSharedDrives() throws {
        let home = try FakeCloud.home()
        let accounts = CloudPlaces.driveAccounts(home: home)
        #expect(accounts.map(\.email) == ["ana@studio.com", "old@studio.com", "ana.lopez@gmail.com"])
        let work = accounts[0]
        #expect(work.state == .ready && !work.isPersonal && work.canHaveSharedDrives)
        #expect(work.sharedDrives.map(\.name) == ["Design", "Marketing"])
        #expect(work.myDrive?.lastPathComponent == "My Drive")
        #expect(accounts[1].state == .empty)                         // signed out: the folder stays behind, empty
        #expect(accounts[2].isPersonal && !accounts[2].canHaveSharedDrives && accounts[2].sharedDrives.isEmpty)
        #expect(CloudPlaces.preferred(accounts)?.email == "ana@studio.com")
        #expect(CloudPlaces.driveAccounts(home: TestSupport.tempDir()).isEmpty)
    }

    @Test func aWorkAccountWithoutSharedDrivesIsStillPreferredOverAPersonalOne() throws {
        let home = try FakeCloud.home(sharedDrives: [])
        let accounts = CloudPlaces.driveAccounts(home: home)
        #expect(accounts[0].sharedDrives.isEmpty && accounts[0].sharedDrivesFolder != nil)
        #expect(CloudPlaces.preferred(accounts)?.email == "ana@studio.com")
        #expect(CloudPlaces.preferred([accounts[2]])?.email == "ana.lopez@gmail.com")
    }

    @Test func anAccountMacOSWontListIsUnreadableNotEmpty() throws {
        let home = try FakeCloud.home(unreadable: true)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home.appendingPathComponent(FakeCloud.work).path) }
        let work = CloudPlaces.driveAccounts(home: home).first { $0.email == "ana@studio.com" }
        #expect(work?.state == .unreadable)
        #expect(CloudPlaces.preferred(CloudPlaces.driveAccounts(home: home))?.email == "ana.lopez@gmail.com")
    }

    @Test func otherSyncClientsAreAllListed() throws {
        let roots = CloudPlaces.otherRoots(home: try FakeCloud.home())
        #expect(roots.map(\.service) == [.dropbox])
    }
}

@Suite struct LibraryPlacementTests {
    let home = URL(fileURLWithPath: "/Users/ana")
    func place(_ p: String) -> Placement { Placement.of(home.appendingPathComponent(p), home: home) }

    @Test func tellsSharedDrivesFromMyDriveAndTheRest() {
        let sd = place("\(FakeCloud.work)/Shared drives/Design/Refs/Team Inspo.grails")
        #expect(sd.kind == .sharedDrive("Design") && sd.account == "ana@studio.com" && sd.label == "Shared drive Design")
        #expect(sd.relativePath == "Shared drives/Design/Refs/Team Inspo.grails")
        #expect(place("\(FakeCloud.work)/My Drive/Team.grails").kind == .myDrive)
        #expect(place("\(FakeCloud.work)/Other computers/Mac/Team.grails").kind == .otherComputers)
        #expect(place("\(FakeCloud.work)/.shortcut-targets-by-id/1AbC/Team.grails").kind == .sharedWithMe)
        #expect(place("\(FakeCloud.work)/Shared drives").kind == .driveTop)
        #expect(place("\(FakeCloud.work)").kind == .driveTop)
        #expect(place("Library/CloudStorage/Dropbox/Studio/Team.grails").kind == .cloud(.dropbox))
        #expect(place("Library/Mobile Documents/com~apple~CloudDocs/Team.grails").kind == .cloud(.iCloud))
        #expect(place("My Drive/Team.grails").kind == .myDrive)                    // Drive in Mirror mode
        #expect(place("Pictures/Grails Library.grails").kind == .local)
        #expect(place(".Trash/Team.grails").inTrash)
        #expect(place("\(FakeCloud.work)/My Drive/.Trash/Team.grails").inTrash)
    }

    @Test func aLibraryInASharedDriveThatDriveHasPassesCleanly() {
        let p = place("\(FakeCloud.work)/Shared drives/Design/Team Inspo.grails")
        let r = PlacementReport(placement: p, facts: FileFacts(driveItemID: "1a2B3c4D5e6F7g8H9i0J"))
        #expect(r.issues.isEmpty && r.canContinue && !r.waiting)
        #expect(r.rows.map(\.state) == [.ok, .ok, .ok])
    }

    @Test func warnsAboutEveryPlaceTeammatesWouldNotGetRight() {
        let accounts = [DriveAccount(email: "ana@studio.com", root: home, state: .ready), DriveAccount(email: "ana.lopez@gmail.com", root: home, state: .ready)]
        func issues(_ p: String, _ f: FileFacts = FileFacts(driveItemID: "1a2B3c4D5e6F7g8H9i0J")) -> [PlacementIssue] { PlacementReport(placement: place(p), facts: f, accounts: accounts).issues }
        #expect(issues("Pictures/Lib.grails") == [.local])
        #expect(!PlacementReport(placement: place("Pictures/Lib.grails"), facts: FileFacts()).canContinue)
        #expect(issues("\(FakeCloud.work)/My Drive/.Trash/Lib.grails").contains(.trash))
        #expect(issues("\(FakeCloud.work)/My Drive/Lib.grails") == [.myDrive])
        #expect(issues("\(FakeCloud.work)/Other computers/Mac/Lib.grails") == [.otherComputers])
        #expect(issues("\(FakeCloud.personal)/My Drive/Lib.grails") == [.myDrive, .personalAccount("ana.lopez@gmail.com")])
        // just made: Drive hasn't written its id yet, so the screen waits (and doesn't block)
        let fresh = PlacementReport(placement: place("\(FakeCloud.work)/Shared drives/Design/Lib.grails"), facts: FileFacts())
        #expect(fresh.issues == [.notUploaded] && fresh.waiting && fresh.canContinue && fresh.rows[1].state == .waiting)
        // after a long wait with no word from Drive it says it can't tell instead of waiting for ever
        let long = PlacementReport(placement: place("\(FakeCloud.work)/Shared drives/Design/Lib.grails"), facts: FileFacts(), waitedLong: true)
        #expect(long.issues.isEmpty && long.rows[1].state == .unknown)
        #expect(issues("\(FakeCloud.work)/Shared drives/Design/Lib.grails", FileFacts(uploadError: "Quota exceeded")) == [.uploadFailed("Quota exceeded")])
        #expect(issues("\(FakeCloud.work)/Shared drives/Design/Lib.grails", FileFacts(driveItemID: "1a2B3c4D5e6F7g8H9i0J", manifestOnlineOnly: true)) == [.onlineOnly])
        #expect(issues("Library/CloudStorage/Dropbox/Lib.grails", FileFacts()).isEmpty)
        #expect(issues("Library/CloudStorage/Dropbox/Lib.grails", FileFacts(uploading: true)) == [.notUploaded])
        #expect(PlacementIssue.myDrive.detail.contains("Shared drive"))
    }
}

@Suite struct DriveItemIDTests {
    @Test func readsDrivesIdFromTheAttributeAndBuildsTheFolderPage() {
        let reader: DriveItemID.Reader = { _, name in name == "com.google.drivefs.item-id#S" ? Data("1AbCdEfGhIjKlMnOpQrStUvWxYz012345\0".utf8) : nil }
        let id = DriveItemID.read(URL(fileURLWithPath: "/x"), reader: reader)
        #expect(id == "1AbCdEfGhIjKlMnOpQrStUvWxYz012345")
        #expect(DriveWeb.folder(id: id!, account: "ana@studio.com").absoluteString == "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz012345?authuser=ana@studio.com")
        #expect(DriveItemID.read(URL(fileURLWithPath: "/x"), reader: { _, _ in nil }) == nil)
        #expect(DriveItemID.read(URL(fileURLWithPath: "/x"), reader: { _, _ in Data("local-42".utf8) }) == nil)
        #expect(DriveItemID.read(URL(fileURLWithPath: "/x"), reader: { _, _ in Data("../../etc".utf8) }) == nil)
        #expect(DriveItemID.isValid("0AHq6dkTgXyZUk9PVA"))
    }

    @Test func withoutAnIdItOpensTheListTheFolderIsIn() {
        let home = URL(fileURLWithPath: "/Users/ana")
        let sd = Placement.of(home.appendingPathComponent("\(FakeCloud.work)/Shared drives/Design/T.grails"), home: home)
        #expect(DriveWeb.page(for: sd, folderID: nil).absoluteString == "https://drive.google.com/drive/shared-drives?authuser=ana@studio.com")
        #expect(DriveWeb.page(for: sd, folderID: "1AbCdEfGhIjKlMnOpQrS").path == "/drive/folders/1AbCdEfGhIjKlMnOpQrS")
        let md = Placement.of(home.appendingPathComponent("\(FakeCloud.work)/My Drive/T.grails"), home: home)
        #expect(DriveWeb.page(for: md, folderID: nil).path == "/drive/my-drive")
    }

    @Test func readsARealAttributeFromDisk() throws {
        let dir = TestSupport.tempDir()
        let value = "1AbCdEfGhIjKlMnOpQrStUv"
        let rc = value.withCString { v in setxattr(dir.path, "com.google.drivefs.item-id#S", v, strlen(v), 0, 0) }
        #expect(rc == 0)
        #expect(DriveItemID.read(dir) == value)
        #expect(FileFacts.read(library: dir).driveItemID == value)
    }
}

@Suite struct InviteTextTests {
    let page = URL(string: "https://grails.arjoon.xyz/open")!
    let hint = LibraryHint(kind: .sharedDrive, place: "Design", domain: "studio.com")

    @Test func theLinkCarriesWhereTheLibraryLivesAfterTheHash() throws {
        let link = InviteText.link(libraryID: "01ABC", name: "Team Inspo", hint: hint, page: page)
        #expect(link.absoluteString == "https://grails.arjoon.xyz/open#lib=01ABC&name=Team%20Inspo&k=sd&at=Design&dom=studio.com")
        #expect(link.query == nil)
        let back = try #require(GrailsLink(url: link))
        #expect(back.library == "01ABC" && back.name == "Team Inspo" && back.hint == hint)
        // links made before hints, and the router page passing only the keys it knows, still work
        #expect(GrailsLink(text: "https://grails.arjoon.xyz/open#lib=01ABC&name=Team%20Inspo")?.hint == nil)
        #expect(GrailsLink(text: "grails://open?lib=01ABC&k=zz")?.hint == nil)
        let placement = Placement.of(URL(fileURLWithPath: "/Users/ana/\(FakeCloud.work)/Shared drives/Design/T.grails"), home: URL(fileURLWithPath: "/Users/ana"))
        #expect(LibraryHint(placement: placement) == hint)
        #expect(LibraryHint(placement: Placement(kind: .local)) == nil)
    }

    @Test func theInviteSaysWhereItIsAndWhatToDoInOrder() {
        let link = InviteText.link(libraryID: "01ABC", name: "Team Inspo", hint: hint, page: page)
        let m = InviteText.invite(library: "Team Inspo", link: link, hint: hint, from: "arjun")
        #expect(m.subject == "Join Team Inspo on Grails")
        #expect(m.body == """
        Hi,

        I've set up Team Inspo, our team's picture library in Grails. It lives in the Shared drive “Design” in our studio.com Google Drive.

        1. Install Google Drive for desktop and sign in with your studio.com account: https://www.google.com/drive/download/
        2. Install Grails: https://grails.arjoon.xyz
        3. Open this link: \(link.absoluteString)

        Grails finds the library in your Google Drive by itself. If it can't, it says what's missing.

        arjun
        """)
        let my = InviteText.invite(library: "Refs", link: link, hint: LibraryHint(kind: .myDrive, domain: "gmail.com"), from: "")
        #expect( my.body.contains("a folder in my Google Drive") && my.body.contains("Organize ▸ Add shortcut ▸ My Drive"))
        let dropbox = InviteText.invite(library: "Refs", link: link, hint: LibraryHint(kind: .dropbox), from: "a")
        #expect(dropbox.body.contains("Accept the shared folder in Dropbox") && !dropbox.body.contains("Google"))
    }

    @Test func theAccessRequestNamesWhatToAddAndWho() {
        let r = InviteText.accessRequest(library: "Team Inspo", hint: hint, myEmails: ["ben@studio.com"], link: nil)
        #expect(r.subject == "Access to Team Inspo")
        #expect(r.body.contains("Could you add me (ben@studio.com) to the Shared drive “Design” as a Content manager?"))
        #expect(InviteText.accessRequest(library: "R", hint: LibraryHint(kind: .myDrive), myEmails: [], link: nil).body.contains("share the folder with me as an Editor"))
    }
}

@Suite struct SeenPeopleTests {
    @Test func seenPeopleFoldPresenceAndContributionsTogether() {
        let t = Date(timeIntervalSince1970: 0)
        let seen = SeenPerson.merge(members: [MemberRecord(handle: "ana", firstSeen: t, lastSeen: t), MemberRecord(handle: "cleo", firstSeen: t, lastSeen: t)],
                                    contributors: [(who: "ana", count: 3), (who: "Ben", count: 1)])
        #expect(seen == [SeenPerson(handle: "ana", items: 3, opened: true), SeenPerson(handle: "Ben", items: 1), SeenPerson(handle: "cleo", opened: true)])
    }
}

@Suite struct MembersTests {
    @Test func eachPersonWritesTheirOwnRecordAtMostOnceADay() throws {
        let layout = LibraryLayout(root: TestSupport.tempDir().appendingPathComponent("T.grails"))
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(try Members.record(handle: "ana", in: layout, now: t0))
        #expect(try !Members.record(handle: "ana", in: layout, now: t0.addingTimeInterval(3600)))
        #expect(try Members.record(handle: "ana", in: layout, now: t0.addingTimeInterval(90_000)))
        #expect(try Members.record(handle: "Ben Ito", in: layout, now: t0))
        #expect(try !Members.record(handle: "***", in: layout, now: t0))
        let all = Members.all(in: layout)
        #expect(all.map(\.handle) == ["ana", "Ben Ito"])
        #expect(all[0].firstSeen == t0 && all[0].lastSeen == t0.addingTimeInterval(90_000))
        #expect(FileManager.default.fileExists(atPath: layout.root.appendingPathComponent(".members/ben-ito.json").path))
    }
}

@Suite struct JoinDiagnosisTests {
    let hint = LibraryHint(kind: .sharedDrive, place: "Design", domain: "studio.com")
    func account(_ email: String, _ state: DriveAccount.State = .ready) -> DriveAccount { DriveAccount(email: email, root: URL(fileURLWithPath: "/x/\(email)"), state: state) }

    @Test func saysWhichCaseItLooksLike() {
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: false, accounts: [])) == .noApp(.googleDrive))
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: true, accounts: [])) == .notSignedIn)
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: true, accounts: [account("a@studio.com", .empty)])) == .notSignedIn)
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: true, accounts: [account("a@studio.com", .unreadable)])) == .cannotRead)
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: true, accounts: [account("ben@gmail.com")])) == .wrongAccount(domain: "studio.com", signedIn: ["ben@gmail.com"]))
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: true, accounts: [account("ben@gmail.com"), account("ben@studio.com")])) == .notShared(signedIn: ["ben@studio.com"]))
        // without a hint (an older link, or the router page dropped it) it can't name the account, so it doesn't
        #expect(JoinDiagnosis.diagnose(hint: nil, facts: JoinFacts(driveAppInstalled: true, accounts: [account("ben@gmail.com")])) == .notShared(signedIn: ["ben@gmail.com"]))
        // a personal Drive could have been shared with anyone: no account complaint
        #expect(JoinDiagnosis.diagnose(hint: LibraryHint(kind: .myDrive, domain: "gmail.com"), facts: JoinFacts(driveAppInstalled: true, accounts: [account("b@studio.com")])) == .notShared(signedIn: ["b@studio.com"]))
        #expect(JoinDiagnosis.diagnose(hint: LibraryHint(kind: .dropbox), facts: JoinFacts(driveAppInstalled: true, accounts: [account("b@studio.com")])) == .noApp(.dropbox))
        #expect(JoinDiagnosis.diagnose(hint: LibraryHint(kind: .dropbox), facts: JoinFacts(driveAppInstalled: false, accounts: [], otherServices: [.dropbox])) == .notShared(signedIn: []))
        let url = URL(fileURLWithPath: "/x/T.grails")
        #expect(JoinDiagnosis.diagnose(hint: hint, facts: JoinFacts(driveAppInstalled: false, accounts: [], found: url)) == .found(url))
    }

    @Test func eachCaseHasOneMainActionAndTheWayOut() {
        let cases: [JoinDiagnosis] = [.noApp(.googleDrive), .noApp(.dropbox), .notSignedIn, .cannotRead, .wrongAccount(domain: "studio.com", signedIn: ["b@gmail.com"]), .notShared(signedIn: ["b@studio.com"])]
        for c in cases {
            for h in [hint, LibraryHint(kind: .myDrive, domain: "studio.com"), nil] as [LibraryHint?] {
                let copy = c.copy(library: "Team Inspo", hint: h)
                #expect(!copy.title.isEmpty && !copy.steps.isEmpty && copy.secondary.contains(.locate) && copy.secondary.contains(.checkAgain))
                #expect(!copy.secondary.contains(copy.primary))
            }
        }
        let shared = JoinDiagnosis.notShared(signedIn: ["ben@studio.com"]).copy(library: "Team Inspo", hint: hint)
        #expect(shared.title == "Not shared with you yet" && shared.primary == .askForAccess)
        #expect(shared.detail == "Team Inspo is in the Shared drive “Design”, which isn't in your Drive (ben@studio.com).")
        #expect(JoinDiagnosis.notShared(signedIn: []).copy(library: "T", hint: LibraryHint(kind: .myDrive)).primary == .openSharedWithMe)
        #expect(JoinDiagnosis.noApp(.googleDrive).copy(library: "T", hint: hint).steps[1] == "Sign in with your studio.com account")
    }

    @Test func openingTheFolderAroundALibraryUsesTheLibrary() throws {
        let home = try FakeCloud.home()
        let refs = home.appendingPathComponent("References")
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        let lib = try FakeCloud.makeLibrary("References/Team Library.grails", in: home, id: "01T", name: "Team Library")
        #expect(LibraryFinder.picked(refs)?.standardizedFileURL == lib.standardizedFileURL)
        #expect(LibraryFinder.picked(lib, named: "Team Library")?.standardizedFileURL == lib.standardizedFileURL)
        _ = try FakeCloud.makeLibrary("References/Other.grails", in: home, id: "01O", name: "Other")
        #expect(LibraryFinder.picked(refs) == nil)
        #expect(LibraryFinder.picked(refs, named: "Team Library")?.standardizedFileURL == lib.standardizedFileURL)
    }

    @Test func findsTheLibraryWhereverDriveShowsIt() throws {
        let home = try FakeCloud.home()
        let accounts = { CloudPlaces.driveAccounts(home: home) }
        #expect(LibraryFinder.find(id: "01T", accounts: accounts(), hint: hint) == nil)
        _ = try FakeCloud.makeLibrary("\(FakeCloud.work)/Shared drives/Marketing/Other.grails", in: home, id: "01O", name: "Other")
        let lib = try FakeCloud.makeLibrary("\(FakeCloud.work)/Shared drives/Design/Refs/2026/Team Inspo.grails", in: home, id: "01T", name: "Team Inspo")
        #expect(LibraryFinder.find(id: "01T", accounts: accounts(), hint: hint)?.standardizedFileURL == lib.standardizedFileURL)
        #expect(LibraryFinder.find(id: "01T", accounts: accounts(), hint: nil)?.standardizedFileURL == lib.standardizedFileURL)
        // a folder shared from someone's My Drive, added as a shortcut: Drive keeps it apart and links it into My Drive
        let shared = try FakeCloud.makeLibrary("\(FakeCloud.work)/.shortcut-targets-by-id/1XyZ/Refs.grails", in: home, id: "01R", name: "Refs")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("\(FakeCloud.work)/My Drive/Refs.grails"), withDestinationURL: shared)
        #expect(LibraryFinder.find(id: "01R", accounts: accounts(), hint: LibraryHint(kind: .myDrive)) != nil)
        let dropboxLib = try FakeCloud.makeLibrary("Library/CloudStorage/Dropbox/Studio/D.grails", in: home, id: "01D", name: "D")
        #expect(LibraryFinder.find(id: "01D", accounts: [], otherRoots: CloudPlaces.otherRoots(home: home).map(\.root.url))?.standardizedFileURL == dropboxLib.standardizedFileURL)
    }
}

@Suite struct CollabSetupFlowTests {
    @Test func walksForwardOnlyWhenEachStepIsDone() {
        var f = CollabSetupFlow(current: Placement(kind: .local))
        #expect(f.step == .service)
        f.send(.libraryReady); #expect(f.step == .service)
        f.send(.choseService); #expect(f.step == .place)
        f.send(.libraryReady); #expect(f.step == .check)
        f.send(.checked(canContinue: false)); #expect(f.step == .check)
        f.send(.checked(canContinue: true)); #expect(f.step == .share)
        f.send(.shared); #expect(f.step == .invite)
        f.send(.invited); #expect(f.step == .done)
        f.send(.back); #expect(f.step == .invite)
        #expect(CollabSetupFlow(current: Placement(kind: .sharedDrive("Design"), account: "a@b.co")).step == .check)
        #expect(CollabSetupFlow(current: Placement(kind: .myDrive, inTrash: true)).step == .service)
        var g = CollabSetupFlow(step: .check); g.send(.changeFolder); #expect(g.step == .place)
    }
}

import GRDB

@Suite struct IndexDamageTests {
    @Test func diskErrorsMeanTheIndexIsRebuiltNotThatTheLibraryIsBad() {
        #expect(LibraryIndex.isDamaged(DatabaseError(resultCode: .SQLITE_IOERR, message: "disk I/O error")))
        #expect(LibraryIndex.isDamaged(DatabaseError(resultCode: .SQLITE_CORRUPT)))
        #expect(!LibraryIndex.isDamaged(DatabaseError(resultCode: .SQLITE_CONSTRAINT)))
        #expect(!LibraryIndex.isDamaged(GrailsError.itemNotFound("x")))
    }
}
