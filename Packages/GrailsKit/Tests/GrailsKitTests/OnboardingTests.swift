import Foundation
import Testing
@testable import GrailsKit

@Suite struct HandleTests {
    @Test func handlesAreLowercaseAndTidy() {
        #expect(Handle.normalize("Arjun V.") == "arjun-v")
        #expect(Handle.normalize("  Ana María ") == "ana-maria")
        #expect(Handle.normalize("ben_the.builder") == "ben_the.builder")
        #expect(Handle.normalize("***") == "")
        #expect(Handle.normalize(String(repeating: "a", count: 50)).count == 32)
    }
}

@Suite struct SyncedRootsTests {
    func tree() throws -> URL {
        let home = TestSupport.tempDir()
        let fm = FileManager.default
        for d in ["Library/CloudStorage/GoogleDrive-ana@studio.com/Shared drives/Design/Team Inspo.grails",
                  "Library/CloudStorage/Dropbox/Projects", "Library/CloudStorage/OneDrive-Studio", "Library/CloudStorage/Box-Box",
                  "Library/Mobile Documents/com~apple~CloudDocs/Old/Mine.stash"] {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        for lib in ["Library/CloudStorage/GoogleDrive-ana@studio.com/Shared drives/Design/Team Inspo.grails", "Library/Mobile Documents/com~apple~CloudDocs/Old/Mine.stash"] {
            try Data(#"{"id":"01X","name":"\#(URL(fileURLWithPath: lib).deletingPathExtension().lastPathComponent)","schema":1,"createdAt":"2026-01-01T00:00:00.000Z"}"#.utf8).write(to: home.appendingPathComponent(lib + "/library.json"))
        }
        return home
    }

    @Test func findsSyncedFoldersAndNamesThemForPeople() throws {
        let roots = SyncedRoots.detect(home: try tree())
        #expect(roots.count == 3)                                        // never more than three
        #expect(roots.first?.name == "Box")
        #expect(roots.map(\.name).contains("Dropbox") || roots.map(\.name).contains("Google Drive"))
        #expect(SyncedRoots.displayName("GoogleDrive-ana@studio.com") == "Google Drive")
        #expect(SyncedRoots.detect(home: TestSupport.tempDir()).isEmpty)
    }

    @Test func findsLibrariesAlreadyThereIncludingOlderOnes() throws {
        let home = try tree()
        let roots = [SyncedRoot(name: "Google Drive", url: home.appendingPathComponent("Library/CloudStorage/GoogleDrive-ana@studio.com")),
                     SyncedRoot(name: "iCloud Drive", url: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"))]
        let found = SyncedRoots.libraries(in: roots, budget: 2)
        #expect(found.map(\.name).sorted() == ["Mine", "Team Inspo"])
    }
}

@Suite struct OnboardingStateTests {
    @Test func stateSurvivesAQuit() {
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        #expect(OnboardingState.load(defaults) == OnboardingState())
        var s = OnboardingState()
        s.step = .paste; s.libraryPath = "/tmp/x.grails"; s.handle = "ana"
        s.save(defaults)
        #expect(OnboardingState.load(defaults) == s)
        s.done = true; s.save(defaults)
        #expect(OnboardingState.load(defaults).done)
    }
}

@Suite struct ReachableCountTests {
    @Test func pinterestWithoutTheBrowserCountsOnlyItsLatestFifty() {
        let ref = BoardRef.pinterest(user: "ana", board: "interiors")
        #expect(BoardCandidate(ref: ref, name: "I", count: 1204, via: .latest).reachableCount == 50)
        #expect(BoardCandidate(ref: ref, name: "I", count: 30, via: .latest).reachableCount == 30)
        #expect(BoardCandidate(ref: ref, name: "I", count: 1204, via: .browser).reachableCount == 1204)
        var t = BoardTask(candidate: BoardCandidate(ref: ref, name: "I", count: 1204, via: .latest))
        #expect(t.expected == 50)
        t.total = 48
        #expect(t.expected == 48)
    }
}


@Suite struct OnboardingStepMigrationTests {
    @Test func stepsSavedByTheFirstVersionLandOnTheirNewEquivalents() throws {
        func decode(_ step: String) throws -> OnboardingState.Step {
            try JSONDecoder().decode(OnboardingState.self, from: Data(#"{"step":"\#(step)","handle":"","done":false}"#.utf8)).step
        }
        #expect(try decode("library") == .choose && decode("importing") == .paste && decode("arriving") == .arriving && decode("hello") == .hello)
        #expect(try decode("something-else") == .hello)
    }
}


@Suite struct InviteLinkPageTests {
    @Test func linksOnTheSiteCarryTheirDetailsAfterTheHashAndComeBackAsTheSameLink() throws {
        let page = try #require(URL(string: "https://grails.arjoon.xyz/open"))
        let link = GrailsLink(library: "01ABC", name: "Team Inspo", target: .collection("c1"), canvas: true)
        let web = link.webURL(page: page)
        #expect(web.absoluteString.hasPrefix("https://grails.arjoon.xyz/open#lib=01ABC"))
        #expect(web.query == nil)                                     // nothing the server could see
        #expect(GrailsLink(url: web) == link)
        #expect(GrailsLink(text: "  \(web.absoluteString)\n") == link)
    }
}
