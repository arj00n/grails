import Foundation
import Testing
@testable import GrailsKit

@Suite struct TagSelectionTests {
    /// What Vision returned for an aerial photo of a bridge over a lake (real output, abridged).
    let aerial: [(String, Float)] = [
        ("structure", 0.97), ("rocks", 0.95), ("outdoor", 0.84), ("bridge", 0.84), ("land", 0.77), ("hill", 0.76),
        ("sky", 0.71), ("blue_sky", 0.70), ("liquid", 0.68), ("water", 0.68), ("water_body", 0.68), ("lake", 0.68), ("cloudy", 0.12),
    ]

    @Test func dropsRootsAndRepeatedWords() {
        // the built-in list is only the classifier's meaningless roots; domain noise is learned per library instead
        let tags = ImageTagger.select(aerial, options: .init(minConfidence: 0.5, maxTags: 8)).map(\.tag)
        #expect(!tags.contains("structure"))
        #expect(tags.contains("outdoor") && tags.contains("land"))               // not meaningless in every library
        let narrowed = ImageTagger.select(aerial, options: .init(minConfidence: 0.5, maxTags: 8, denylist: ImageTaggerOptions.defaultDenylist.union(["outdoor", "land", "liquid"]))).map(\.tag)
        #expect(narrowed.contains("rocks") && narrowed.contains("bridge") && narrowed.contains("hill") && narrowed.contains("lake"))
        #expect(narrowed.contains("sky") && !narrowed.contains("blue sky"))     // one sky tag, not two
        #expect(narrowed.contains("water") && !narrowed.contains("water body"))
        #expect(!narrowed.contains("cloudy"))                                    // under the floor
    }

    @Test func bestFirstAndCapped() {
        let tags = ImageTagger.select(aerial, options: .init(minConfidence: 0.5, maxTags: 3))
        #expect(tags.map(\.tag) == ["rocks", "bridge", "outdoor"])
        #expect(tags.map(\.confidence) == tags.map(\.confidence).sorted(by: >))
        #expect(ImageTagger.select(aerial, options: .init(minConfidence: 0.99, maxTags: 5)).isEmpty)
        #expect(ImageTagger.select([], options: .init()).isEmpty)
        #expect(ImageTagger.select(aerial, options: .init(minConfidence: 0.5, maxTags: 0)).isEmpty)
    }

    @Test func normalisationAndTies() {
        #expect(ImageTagger.normalize("Hot_Dog") == "hot dog")
        let tied = ImageTagger.select([("zebra", 0.8), ("apple", 0.8), ("mango", 0.8)], options: .init(minConfidence: 0.5, maxTags: 5)).map(\.tag)
        #expect(tied == ["apple", "mango", "zebra"])                            // same confidence ⇒ alphabetical, always
        // a multi-word label blocks a later label that shares one of its words
        #expect(ImageTagger.select([("ice_cream", 0.9), ("cream", 0.8), ("cone", 0.7)], options: .init()).map(\.tag) == ["ice cream", "cone"])
    }

    @Test func customDenylistAndSensitivity() {
        let opts = ImageTaggerOptions(minConfidence: 0.5, maxTags: 5, denylist: ["rocks"])
        #expect(!ImageTagger.select(aerial, options: opts).map(\.tag).contains("rocks"))
        let few = ImageTaggerOptions.sensitivity(0), many = ImageTaggerOptions.sensitivity(1), mid = ImageTaggerOptions.sensitivity(0.5)
        #expect(few.minConfidence > mid.minConfidence && mid.minConfidence > many.minConfidence)
        #expect(few.maxTags < mid.maxTags && mid.maxTags < many.maxTags)
        #expect(ImageTaggerOptions.sensitivity(-4) == few && ImageTaggerOptions.sensitivity(9) == many)
        #expect(ImageTagger.select(aerial, options: few).count <= ImageTagger.select(aerial, options: many).count)
    }
}

@Suite struct AutoTaggerTests {
    func stub(_ map: [String: [String]]) -> TagClassifier {
        { url, _ in
            let name = url.deletingLastPathComponent().lastPathComponent        // …/items/<id>/thumb.jpg
            return (map[name] ?? ["generic"]).map { TagSuggestion(tag: $0, confidence: 0.9) }
        }
    }

    func library(_ n: Int, handle: String = "ana") async throws -> (LibraryStore, [Item]) {
        let (store, _) = try TestSupport.newStore(handle: handle)
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<n {
            items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "p\(i)", rgb: (Double(i) / Double(max(n, 1)), 0.3, 0.6))).item)
            try await Task.sleep(for: .milliseconds(3))
        }
        return (store, items)
    }

    @Test func tagsPendingItemsNewestFirstAndRemembersIt() async throws {
        let (store, items) = try await library(4)
        let tagger = AutoTagger(store: store, classify: stub([items[0].id: ["old"], items[3].id: ["new", "shiny"]]))
        #expect(await tagger.pendingCount() == 4)
        final class Order: @unchecked Sendable { var ids: [Int] = []; let lock = NSLock() }
        let progress = Order()
        let s = await tagger.run { done, total in progress.lock.lock(); progress.ids.append(done * 100 + total); progress.lock.unlock() }
        #expect(s.checked == 4 && s.tagged == 4 && s.tagsAdded == 5 && s.skipped == 0 && s.failed == 0)
        #expect(progress.ids == [4, 104, 204, 304, 404])                         // 0/4 … 4/4
        #expect(try await store.item(id: items[3].id)?.tags == ["new", "shiny"])
        #expect(try await store.item(id: items[3].id)?.autoTags == ["new", "shiny"])
        #expect(try await store.item(id: items[3].id)?.isAutoTagged == true)
        #expect(await tagger.pendingCount() == 0)
        #expect(await tagger.run().checked == 0)                                 // nothing left; a re-run does nothing
    }

    @Test func neverTouchesWhatAPersonDidAndNeverReAddsRemovedTags() async throws {
        let (store, items) = try await library(1)
        let id = items[0].id
        try await store.addTags(["mine"], to: [id])
        let tagger = AutoTagger(store: store, classify: stub([id: ["mine", "robot"]]))
        #expect(await tagger.run().tagsAdded == 1)                               // "mine" already there (any case) → only "robot"
        #expect(try await store.item(id: id)?.tags == ["mine", "robot"])
        #expect(try await store.item(id: id)?.autoTags == ["robot"])             // "mine" was the person's, not the machine's
        try await store.removeTags(["robot"], from: [id])
        #expect(try await store.item(id: id)?.autoTags == [])                    // removed tags stop counting as automatic
        #expect(await tagger.run().checked == 0)                                 // and the next run doesn't put it back
        #expect(try await store.item(id: id)?.tags == ["mine"])
        // an explicit "tag these again" does re-run
        #expect(await tagger.run(ids: [id]).tagsAdded == 1)
        #expect(try await store.item(id: id)?.tags == ["mine", "robot"])
    }

    @Test func onlyYourOwnItemsWhenAsked() async throws {
        let (store, mine) = try await library(2, handle: "ana")
        await store.setUserHandle("ben")
        let bens = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "ben", rgb: (0.9, 0.1, 0.1))).item
        let tagger = AutoTagger(store: store, classify: stub([:]))
        let (ana, ben, all) = (await tagger.pendingCount(addedBy: "ana"), await tagger.pendingCount(addedBy: "ben"), await tagger.pendingCount())
        #expect(ana == 2 && ben == 1 && all == 3)
        let s = await tagger.run(addedBy: "ben")
        #expect(s.checked == 1)
        #expect(try await store.item(id: bens.id)?.isAutoTagged == true)
        #expect(try await store.item(id: mine[0].id)?.isAutoTagged == false)
    }

    @Test func itemsWithoutALocalPictureAreSkippedNotFailed() async throws {
        let (store, items) = try await library(2)
        try FileManager.default.removeItem(at: store.layout.thumbURL(items[0].id))
        try FileManager.default.removeItem(at: store.layout.itemDir(items[0].id).appendingPathComponent("original.png"))
        let s = await AutoTagger(store: store, classify: stub([:])).run()
        #expect(s.skipped == 1 && s.tagged == 1 && s.failed == 0)
        #expect(try await store.item(id: items[0].id)?.isAutoTagged == false)    // stays pending until a picture exists
    }

    @Test func classifierFailuresAreCountedAndRetriedLater() async throws {
        let (store, items) = try await library(2)
        struct Boom: Error {}
        let tagger = AutoTagger(store: store, classify: { url, _ in
            if url.deletingLastPathComponent().lastPathComponent == items[0].id { throw Boom() }
            return [TagSuggestion(tag: "ok", confidence: 1)]
        })
        let s = await tagger.run()
        #expect(s.failed == 1 && s.tagged == 1)
        #expect(await tagger.pendingCount() == 1)                                // the failed one is still pending
    }

    @Test func autoTaggingIsNotPartOfUndoAndSyncsAsAnOrdinaryEdit() async throws {
        let (store, items) = try await library(1)
        let tagger = AutoTagger(store: store, classify: stub([:]))
        let (_, undo) = try await store.recording(label: "Something else") { await tagger.run() }
        #expect(undo.isEmpty)                                                    // background work never lands in someone's undo stack
        let item = try #require(try await store.item(id: items[0].id))
        #expect(item.tags == ["generic"])
        #expect(item.updatedBy == "ana")
        // another Mac reads it through the normal path: the tags are in the index
        #expect(try await store.index.query(ItemQuery(text: "generic")).map(\.id) == [items[0].id])
        var q = ItemQuery(); q.tag = "generic"
        #expect(try await store.index.count(q) == 1)
    }

    @Test func cancellationStopsPromptly() async throws {
        let (store, _) = try await library(30)
        let tagger = AutoTagger(store: store, classify: { _, _ in try await Task.sleep(for: .milliseconds(20)); return [TagSuggestion(tag: "t", confidence: 1)] })
        let task = Task { await tagger.run() }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let s = await task.value
        #expect(s.checked < 30 && s.checked > 0)
    }

    @Test func linksWithPreviewImagesAreTaggedFromTheirThumbnail() async throws {
        let (store, _) = try TestSupport.newStore()
        let preview = try Data(contentsOf: TestSupport.makePNG(in: TestSupport.tempDir(), name: "og", width: 200, height: 120))
        let linkItem = try await store.addLink(url: URL(string: "https://x.test/a")!, title: "A", site: "x.test", previewImage: preview).item
        let bare = try await store.addLink(url: URL(string: "https://x.test/b")!, title: "B", site: "x.test").item     // no picture at all
        let s = await AutoTagger(store: store, classify: { _, _ in [TagSuggestion(tag: "poster", confidence: 1)] }).run()
        #expect(s.tagged == 1 && s.skipped == 1)
        #expect(try await store.item(id: linkItem.id)?.tags == ["poster"])
        #expect(try await store.item(id: bare.id)?.isAutoTagged == false)
    }
}

@Suite struct LearnedNoiseTests {
    /// 50 items, each classified as "plate" plus its own unique tag.
    func library(_ n: Int = 50) async throws -> (LibraryStore, [Item], AutoTagger) {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<n { items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "p\(i)", rgb: (Double(i % 7) / 7, Double(i / 7) / 8, 0.6))).item) }
        let own = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, "thing\($0)") })
        let tagger = AutoTagger(store: store, classify: { url, options in
            let id = url.deletingLastPathComponent().lastPathComponent
            // like the real classifier: raw labels go through the same selection (floor, denylist, cap)
            return ImageTagger.select([("plate", 0.9), (own[id] ?? "other", 0.8)], options: options)
        })
        return (store, items, tagger)
    }

    @Test func aTagOnMostOfTheLibraryIsRemovedAndRemembered() async throws {
        let (store, items, tagger) = try await library()
        try await store.addTags(["Plate"], to: [items[0].id])                    // a person's own, same tag
        let s = await tagger.run()
        #expect(s.learned == ["plate"])
        #expect(s.pruned == 49)                                                  // every machine-added one; not the person's
        #expect(try await store.item(id: items[0].id)?.tags.contains("Plate") == true)
        #expect(try await store.item(id: items[0].id)?.autoTags.contains("plate") == false)
        #expect(try await store.item(id: items[1].id)?.tags == ["thing1"])       // the specific tag stays
        #expect(try await store.item(id: items[1].id)?.autoTags == ["thing1"])
        let ig = await store.autoTagIgnored()
        #expect(ig == ["plate"])
        #expect(try await store.index.tagCounts().first { $0.tag.lowercased() == "plate" }?.count == 1)
    }

    @Test func newItemsDontGetTheLearnedNoiseBack() async throws {
        let (store, _, tagger) = try await library()
        await tagger.run()
        let more = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "late", rgb: (0.2, 0.9, 0.2))).item
        let s = await tagger.run()
        #expect(s.checked == 1 && s.learned.isEmpty)
        #expect(try await store.item(id: more.id)?.tags == ["other"])            // "plate" skipped, and didn't use up a slot
    }

    @Test func smallLibrariesAreLeftAlone() async throws {
        let (store, items, tagger) = try await library(12)
        let s = await tagger.run()
        #expect(s.learned.isEmpty && s.pruned == 0)
        #expect(try await store.item(id: items[3].id)?.tags == ["plate", "thing3"])
    }

    @Test func aForcedRedoOfChosenItemsNeverLearns() async throws {
        let (store, items, _) = try await library()
        let first = AutoTagger(store: store, classify: { _, _ in [TagSuggestion(tag: "plate", confidence: 1)] })
        await first.run(ids: items.map(\.id))
        let ig = await store.autoTagIgnored()
        #expect(ig.isEmpty)                             // only a bulk run learns
        #expect(try await store.item(id: items[2].id)?.tags == ["plate"])
    }

    @Test func differentLibrariesLearnDifferentNoise() async throws {
        // the same classifier output is noise in one library and a real theme in a smaller, more varied one
        let (food, _, foodTagger) = try await library()
        await foodTagger.run()
        let ig = await food.autoTagIgnored()
        #expect(ig == ["plate"])
        let (decor, items, decorTagger) = try await library(30)
        let s = await decorTagger.run()                                          // under 40 items: "plate" stays a tag
        let none = await decor.autoTagIgnored()
        #expect(s.learned.isEmpty && none.isEmpty)
        #expect(try await decor.item(id: items[0].id)?.tags.contains("plate") == true)
    }

    @Test func deletingATagMeansTheMachineWontBringItBack() async throws {
        let (store, _, tagger) = try await library(12)
        await tagger.run()
        try await store.deleteTag("thing4")
        let ig = await store.autoTagIgnored()
        #expect(ig == ["thing4"])
        #expect(try await store.index.itemIds(withTag: "thing4").isEmpty)
    }

    @Test func resetForgetsWhatWasLearned() async throws {
        let (store, _, tagger) = try await library()
        await tagger.run()
        let learned = await store.autoTagIgnored()
        #expect(!learned.isEmpty)
        try await store.resetAutoTagIgnored()
        let ig = await store.autoTagIgnored()
        #expect(ig.isEmpty)
        try await store.setTagColor("#FF0000", for: "keepme")
        try await store.setAutoTagIgnored(["keepme"], true); try await store.setAutoTagIgnored(["keepme"], false)
        let meta = await store.tagMetadata()
        #expect(meta["keepme"]?.color == "#FF0000")        // colour survives toggling the flag
    }
}

/// The real model, on whatever real photo this Mac has (system wallpapers). Skipped where there isn't one.
@Suite(.serialized) struct VisionIntegrationTests {
    static let candidates = [
        "/System/Library/Wallpapers/.default/DefaultAerial.jpg",
        "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic",
        "/System/Library/PrivateFrameworks/SystemDesktopAppearance.framework/Versions/A/Resources/DefaultBackground.jpg",
    ]
    static var photo: URL? { candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isReadableFile(atPath: $0.path) } }

    @Test(.enabled(if: VisionIntegrationTests.photo != nil))
    func classifiesARealPhotoOnDevice() throws {
        let url = try #require(Self.photo)
        let t0 = Date()
        let tags = try ImageTagger.suggestions(forImageAt: url, options: .init(minConfidence: 0.4, maxTags: 6))
        print("Vision on \(url.lastPathComponent): \(tags.map { "\($0.tag) \(String(format: "%.2f", $0.confidence))" }) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        #expect(!tags.isEmpty)
        #expect(tags.count <= 6)
        #expect(tags.allSatisfy { !$0.tag.contains("_") && $0.tag == $0.tag.lowercased() && $0.confidence >= 0.4 })
        #expect(Set(tags.map(\.tag)).isDisjoint(with: ImageTaggerOptions.defaultDenylist))
    }

    @Test(.enabled(if: VisionIntegrationTests.photo != nil))
    func endToEndThroughTheLibrary() async throws {
        let (store, _) = try TestSupport.newStore()
        let item = try await store.addItem(fileAt: try #require(Self.photo)).item
        #expect(item.tags.isEmpty)
        let summary = await AutoTagger(store: store).run()
        #expect(summary.checked == 1 && summary.failed == 0)
        let tagged = try #require(try await store.item(id: item.id))
        #expect(tagged.isAutoTagged)
        #expect(tagged.tags == tagged.autoTags)
        if case .object(let o)? = tagged.extras["autoTagged"], case .string(let m)? = o["model"] { #expect(m == AutoTagger.engineName) } else { Issue.record("model not recorded") }
    }

    @Test func aBlankImageDoesNotCrashOrInventTags() throws {
        let url = TestSupport.makePNG(in: TestSupport.tempDir(), name: "blank", width: 300, height: 300, rgb: (1, 1, 1))
        let tags = try ImageTagger.suggestions(forImageAt: url, options: .init(minConfidence: 0.8, maxTags: 5))
        #expect(tags.count <= 5)
    }

    @Test func aNonImageFileThrows() throws {
        let url = TestSupport.tempDir().appendingPathComponent("x.jpg")
        try Data("not an image".utf8).write(to: url)
        #expect(throws: (any Error).self) { _ = try ImageTagger.suggestions(forImageAt: url) }
    }
}

@Suite struct TagSimilarityTests {
    @Test func sameWordInDifferentClothes() {
        for (a, b) in [("poster", "posters"), ("Poster", "poster"), ("street-style", "street style"), ("minimal", "minimalist"), ("minimalism", "minimalist"),
                       ("colour", "color"), ("glasses", "glass"), ("berries", "berry"), ("illustration", "illustrations"), ("typography", "typographys"),
                       ("packaging", "packagings"), ("illustrate", "illustrated"),
                       ("minimalistic", "minimalstic")] {
            #expect(TagSimilarity.similar(a, b), "\(a) ~ \(b)")
        }
    }

    @Test func differentWordsStayApart() {
        for (a, b) in [("red", "bed"), ("cream", "dream"), ("dark", "park"), ("stage", "stag"), ("orange", "range"), ("food", "foot"), ("mint", "mind"),
                       ("poster", "post"), ("blue", "blur"), ("glass", "class")] {
            #expect(!TagSimilarity.similar(a, b), "\(a) !~ \(b)")
        }
    }

    @Test func vocabularyWritesTagsTheWayTheLibraryDoes() {
        let v = TagVocabulary(counts: [("poster", 30), ("minimal", 12), ("burger", 5)], aliases: ["hamburger": "burger"])
        #expect(v.canonical("posters") == "poster")
        #expect(v.canonical("Minimalist") == "minimal")
        #expect(v.canonical("hamburger") == "burger")
        #expect(v.canonical("pizza") == "pizza")
        #expect(v.canonical("poster") == "poster")
    }

    @Test func mergeGroupsKeepTheMostUsedOne() {
        let v = TagVocabulary(counts: [("posters", 4), ("poster", 20), ("Poster", 1), ("minimal", 9), ("minimalist", 3), ("food", 7)])
        let g = v.mergeGroups()
        #expect(g.count == 2)
        #expect(g.first { $0.keep == "poster" }?.merge == ["posters"])        // "Poster" is the same tag as "poster" already
        #expect(g.first { $0.keep == "minimal" }?.merge == ["minimalist"])
    }

    @Test func aColouredTagWinsTheMerge() {
        let v = TagVocabulary(counts: [("brand", 20), ("brands", 3)], preferred: ["brands"])
        #expect(v.mergeGroups().first?.keep == "brands")
    }
}

@Suite struct TagNumbersTests {
    @Test func numbersAreNotTypos() {
        #expect(!TagSimilarity.similar("moodboard2024", "moodboard2025"))
        #expect(!TagSimilarity.similar("thing12", "thing13"))
    }
}

@Suite struct TagMergeTests {
    @Test func similarTagsFoldIntoTheMostUsedAndStayFolded() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<5 { items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "m\(i)", rgb: (Double(i) / 5, 0.2, 0.6))).item) }
        try await store.addTags(["poster"], to: [items[0].id, items[1].id, items[2].id])
        try await store.addTags(["Posters", "minimalist"], to: [items[3].id])
        try await store.addTags(["minimal"], to: [items[4].id])

        let merged = try await store.mergeSimilarTags()
        #expect(Set(merged.map(\.from)) == ["Posters", "minimalist"] || Set(merged.map(\.from)) == ["Posters", "minimal"])
        #expect(try await store.item(id: items[3].id)?.tags.contains("poster") == true)
        #expect(try await store.item(id: items[3].id)?.tags.contains("Posters") == false)
        #expect(try await store.index.tagCounts().filter { $0.tag.lowercased().hasPrefix("poster") }.map(\.count) == [4])

        // the machine suggesting the merged-away spelling again writes the surviving one
        let v = try await store.tagVocabulary()
        #expect(v.canonical("posters") == "poster")
        let tagger = AutoTagger(store: store, classify: { _, _ in [TagSuggestion(tag: "posters", confidence: 1)] })
        _ = await tagger.run(ids: [items[4].id])
        #expect(try await store.item(id: items[4].id)?.tags.contains("poster") == true)
    }
}

@Suite struct TagStripQueryTests {
    @Test func extraTagsNarrowTheViewAndAllMustMatch() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<4 { items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "t\(i)", rgb: (Double(i) / 4, 0.5, 0.5))).item) }
        try await store.addTags(["poster", "swiss"], to: [items[0].id, items[1].id])
        try await store.addTags(["poster"], to: [items[2].id])
        var q = ItemQuery()
        q.limit = 100
        #expect(try await store.index.query(q).count == 4)
        q.extraTags = ["poster"]
        #expect(try await store.index.query(q).count == 3)
        q.extraTags = ["poster", "swiss"]
        #expect(Set(try await store.index.query(q).map(\.id)) == [items[0].id, items[1].id])
        q.tag = "swiss"                                          // together with the sidebar's own tag view
        q.extraTags = ["poster"]
        #expect(try await store.index.query(q).count == 2)
        q.extraTags = ["missing"]
        #expect(try await store.index.query(q).isEmpty)
    }
}

@Suite struct ViewTagsTests {
    @Test func tagsAmongSomeItemsCountOnlyThoseItems() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<4 { items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "v\(i)", rgb: (Double(i) / 4, 0.2, 0.8))).item) }
        try await store.addTags(["poster", "swiss"], to: [items[0].id, items[1].id])
        try await store.addTags(["poster", "red"], to: [items[2].id])
        try await store.addTags(["food"], to: [items[3].id])
        let some = try await store.index.tagCounts(among: [items[0].id, items[1].id, items[2].id])
        #expect(some.map(\.tag) == ["poster", "swiss", "red"])
        #expect(some.first?.count == 3 && some[1].count == 2)
        #expect(try await store.index.tagCounts(among: []).isEmpty)
        #expect(!(try await store.index.tagCounts(among: [items[3].id])).contains { $0.tag == "poster" })
    }
}
