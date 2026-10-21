import Foundation
import Testing
@testable import GrailsKit

@Suite struct SyncNudgeTests {
    @Test func aManifestRewriteDoesNotStartAnotherPoll() {
        #expect(!SyncNudge.shouldNudge(paths: ["/Lib/.grails-sync.json"]))
        #expect(!SyncNudge.shouldNudge(paths: []))
    }

    @Test func anItemChangeStillStartsAPoll() {
        #expect(SyncNudge.shouldNudge(paths: ["/Lib/items/a/item.json"]))
        #expect(SyncNudge.shouldNudge(paths: ["/Lib/.grails-sync.json", "/Lib/items/a/item.json"]))
    }

    @Test func theFolderHoldingTheManifestDoesNotStartAnotherPoll() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent(".grails-sync.json")
        try Data("{}".utf8).write(to: manifest)
        let temp = root.appendingPathComponent(".grails-sync.json.atomic")
        try Data("{}".utf8).write(to: temp)
        #expect(!SyncNudge.shouldNudge(paths: [root.path, manifest.path, temp.path]))
        let item = root.appendingPathComponent("items")
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        #expect(SyncNudge.shouldNudge(paths: [item.path]))
    }
}
