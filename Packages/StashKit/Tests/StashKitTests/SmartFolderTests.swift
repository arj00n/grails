import Foundation
import Testing
@testable import StashKit

@Suite struct SmartFolderTests {
    func names(_ store: LibraryStore, _ folder: SmartFolder) async throws -> [String] {
        var q = ItemQuery(); q.smart = folder; q.sort = .nameAsc
        return try await store.index.query(q).map(\.name)
    }

    func folder(_ match: String = "all", _ rules: SmartRule...) -> SmartFolder {
        SmartFolder(name: "t", match: match, rules: rules, updatedBy: "x")
    }

    @Test func fieldsAndOperators() async throws {
        let (store, _) = try TestSupport.newStore()
        let now = Date()
        try await TestSupport.seed(store, [
            TestSupport.item("Reel A", kind: .video, tags: ["motion", "diwali"], w: 1920, h: 1080, bytes: 9_000_000, liked: true, site: "instagram.com", addedAt: now),
            TestSupport.item("Poster 50%", tags: ["print"], w: 600, h: 900, bytes: 400_000, note: "hero", site: "pinterest.com", addedAt: now.addingTimeInterval(-40 * 86400)),
            TestSupport.item("Icon_set", tags: [], w: 512, h: 512, bytes: 20_000, addedAt: now.addingTimeInterval(-2 * 86400), addedBy: "ben"),
        ])
        #expect(try await names(store, folder("all", .init(field: "kind", op: "is", value: "video"))) == ["Reel A"])
        #expect(try await names(store, folder("all", .init(field: "kind", op: "isNot", value: "video"))) == ["Icon_set", "Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "liked", op: "is", value: .bool(true)))) == ["Reel A"])
        #expect(try await names(store, folder("all", .init(field: "hasNote", op: "is", value: .bool(true)))) == ["Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "bytes", op: "gt", value: .int(100_000)))) == ["Poster 50%", "Reel A"])
        #expect(try await names(store, folder("all", .init(field: "width", op: "lte", value: .int(600)))) == ["Icon_set", "Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "aspect", op: "lt", value: .double(1)))) == ["Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "addedAt", op: "withinDays", value: .int(7)))) == ["Icon_set", "Reel A"])
        #expect(try await names(store, folder("all", .init(field: "addedAt", op: "olderThanDays", value: .int(30)))) == ["Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "addedBy", op: "is", value: "ben"))) == ["Icon_set"])
        #expect(try await names(store, folder("all", .init(field: "site", op: "contains", value: "pinterest"))) == ["Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "ext", op: "is", value: "PNG"))).count == 3)
    }

    @Test func tagAndCollectionMembership() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [
            TestSupport.item("a", tags: ["motion"], collections: ["C1": "a"]),
            TestSupport.item("b", tags: ["motion", "print"]),
            TestSupport.item("c"),
        ])
        #expect(try await names(store, folder("all", .init(field: "tags", op: "has", value: "motion"))) == ["a", "b"])
        #expect(try await names(store, folder("all", .init(field: "tags", op: "has", value: "MOTION"), .init(field: "tags", op: "has", value: "print"))) == ["b"])
        #expect(try await names(store, folder("all", .init(field: "tags", op: "hasNot", value: "motion"))) == ["c"])
        #expect(try await names(store, folder("all", .init(field: "tags", op: "empty")))  == ["c"])
        #expect(try await names(store, folder("all", .init(field: "collections", op: "notEmpty"))) == ["a"])
        #expect(try await names(store, folder("all", .init(field: "collections", op: "has", value: "C1"))) == ["a"])
    }

    @Test func matchAnyVsAllAndEmptyRules() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [TestSupport.item("a", tags: ["x"]), TestSupport.item("b", liked: true), TestSupport.item("c")])
        let r1 = SmartRule(field: "tags", op: "has", value: "x"), r2 = SmartRule(field: "liked", op: "is", value: .bool(true))
        #expect(try await names(store, folder("any", r1, r2)) == ["a", "b"])
        #expect(try await names(store, folder("all", r1, r2)) == [])
        #expect(try await names(store, folder("all")) == ["a", "b", "c"])
        #expect(try await names(store, folder("any")) == [])
    }

    @Test func unknownRulesNeverWidenResults() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [TestSupport.item("a", tags: ["x"]), TestSupport.item("b")])
        let good = SmartRule(field: "tags", op: "has", value: "x")
        let bad = SmartRule(field: "futureField", op: "is", value: "1")
        #expect(try await names(store, folder("all", good, bad)) == [])         // can't be proven ⇒ matches nothing
        #expect(try await names(store, folder("any", good, bad)) == ["a"])      // ignored in "any"
        #expect(try await names(store, folder("all", .init(field: "kind", op: "weirdOp", value: "image"))) == [])
    }

    @Test func likeWildcardsInNamesAreEscaped() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [TestSupport.item("Poster 50%"), TestSupport.item("Poster 500"), TestSupport.item("Icon_set"), TestSupport.item("IconXset")])
        #expect(try await names(store, folder("all", .init(field: "name", op: "contains", value: "50%"))) == ["Poster 50%"])
        #expect(try await names(store, folder("all", .init(field: "name", op: "contains", value: "n_s"))) == ["Icon_set"])
    }

    @Test func colorNearMatchesPaletteWithinThreshold() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [
            TestSupport.item("orange", palette: [.init(hex: "#C8742F", weight: 0.5)]),
            TestSupport.item("blue", palette: [.init(hex: "#2F7DC8", weight: 0.5)]),
            TestSupport.item("none"),
        ])
        #expect(try await names(store, folder("all", .init(field: "color", op: "near", value: "#CC7A30"))) == ["orange"])
        #expect(try await names(store, folder("all", .init(field: "color", op: "near", value: .object(["hex": "#2F80C0", "threshold": .int(15)])))) == ["blue"])
        #expect(try await names(store, folder("all", .init(field: "color", op: "near", value: "not-a-colour"))) == [])
    }

    @Test func smartFoldersPersistAndSyncLikeOtherFiles() async throws {
        let (store, root) = try TestSupport.newStore()
        let f = try await store.createSmartFolder(name: "Liked videos", rules: [.init(field: "kind", op: "is", value: "video"), .init(field: "liked", op: "is", value: .bool(true))])
        #expect(await store.smartFolders().map(\.name) == ["Liked videos"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("smart/\(f.id).json").path))
        let second = try await store.createSmartFolder(name: "Second", rules: [])
        #expect(await store.smartFolders().map(\.id) == [f.id, second.id])
        try await store.updateSmartFolder(id: f.id) { $0.name = "Renamed" }
        #expect(await store.smartFolders().first?.name == "Renamed")
        try await store.deleteSmartFolder(id: second.id)
        #expect(await store.smartFolders().count == 1)
    }
}

@Suite struct FuzzyTests {
    @Test func subsequenceMatchingRanksSensibly() {
        let names = ["Biryani shots", "Brass handi", "Bar interiors", "Packaging", "Brynn"]
        let ranked = FuzzyMatcher.rank(names, query: "bryn", text: { $0 })
        #expect(ranked.first == "Brynn")
        #expect(ranked.contains("Biryani shots"))
        #expect(!ranked.contains("Packaging"))
        #expect(FuzzyMatcher.score(query: "xyz", in: "Biryani") == nil)
        #expect(FuzzyMatcher.rank(names, query: "", text: { $0 }) == names)
        #expect(FuzzyMatcher.rank(["Food photography", "Photography food"], query: "ph", text: { $0 }).first == "Photography food")
    }
}
