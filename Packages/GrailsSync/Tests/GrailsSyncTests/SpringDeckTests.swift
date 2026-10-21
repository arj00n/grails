import Foundation
import XCTest
import GrailsSync

final class SpringDeckTests: XCTestCase {
    func testOldestUnopenedComeFirstAndOpenedAreSkipped() {
        let older = item(name: "Older", added: "2020-01-01T00:00:00.000Z", opened: false)
        let newer = item(name: "Newer", added: "2024-06-01T00:00:00Z", opened: false)
        let seen = item(name: "Seen", added: "2019-01-01T00:00:00.000Z", opened: true)
        let deleted = item(name: "Gone", added: "2018-01-01T00:00:00.000Z", opened: false, deleted: true)
        let cards = SpringDeck.rank(items: [
            ("items/new/item.json", newer),
            ("items/seen/item.json", seen),
            ("items/old/item.json", older),
            ("items/gone/item.json", deleted),
            ("notes/x.json", older),
        ])
        XCTAssertEqual(cards.map(\.name), ["Older", "Newer"])
        XCTAssertLessThan(cards[0].addedAt, cards[1].addedAt)
        var deck = SpringDeck(cards: cards)
        XCTAssertEqual(deck.current?.name, "Older")
        deck.keep()
        XCTAssertEqual(deck.current?.name, "Newer")
        deck.keep()
        XCTAssertNil(deck.current)
    }

    func testChuckMovesTheItemToTrashAndMembersCannot() async throws {
        let store = MemoryObjectStore()
        let json = item(name: "Poster", added: "2020-01-01T00:00:00.000Z", opened: false)
        await store.seed("items/poster/item.json", body: json)
        await store.seed("items/poster/original.jpg", body: Data("pixels".utf8))
        do {
            _ = try await SpringTrash.move(store: store, key: "items/poster/item.json", role: .member)
            XCTFail("member")
        } catch SyncFailure.notAllowed {}
        let kept = await store.keys()
        XCTAssertEqual(kept, ["items/poster/item.json", "items/poster/original.jpg"])
        XCTAssertFalse(SpringAccess.allows(.member))
        XCTAssertTrue(SpringAccess.allows(.admin))
        XCTAssertTrue(SpringAccess.allows(.owner))
        let moved = try await SpringTrash.move(store: store, key: "items/poster/item.json", role: .admin)
        XCTAssertEqual(moved, ["items/poster/item.json", "items/poster/original.jpg"])
        let trashed = await store.body("trash/items/poster/original.jpg")
        let live = await store.body("items/poster/item.json")
        XCTAssertEqual(trashed, Data("pixels".utf8))
        XCTAssertNil(live)
        var deck = SpringDeck(cards: SpringDeck.rank(items: [("items/poster/item.json", json)]))
        XCTAssertEqual(deck.current?.key, "items/poster/item.json")
        deck.keep()
        XCTAssertNil(deck.current)
    }

    func testReleaseBelowTheThresholdSpringsBack() {
        var deck = two()
        XCTAssertEqual(deck.release(translation: SpringSwipe.threshold - 1), .springBack)
        XCTAssertEqual(deck.release(translation: -(SpringSwipe.threshold - 1)), .springBack)
        XCTAssertEqual(deck.release(translation: 0), .springBack)
        XCTAssertEqual(deck.current?.name, "Older")
        XCTAssertEqual(deck.cards.map(\.name), ["Older", "Newer"])
        XCTAssertEqual(SpringSwipe.rest(translation: 40, width: 320), 0)
        XCTAssertEqual(SpringSwipe.rotation(translation: 0, width: 320), 0)
    }

    func testDragLeftChucksAndRevealsTheNextCard() {
        var deck = two()
        XCTAssertEqual(deck.release(translation: -SpringSwipe.threshold), .chuck)
        XCTAssertEqual(deck.current?.name, "Newer")
        XCTAssertEqual(deck.release(translation: -200), .chuck)
        XCTAssertNil(deck.current)
        var empty = SpringDeck(cards: [])
        XCTAssertEqual(empty.release(translation: -200), .springBack)
        XCTAssertNil(empty.current)
        XCTAssertLessThan(SpringSwipe.rest(translation: -SpringSwipe.threshold, width: 320), -320)
    }

    func testDragRightKeepsAndRevealsTheNextCard() {
        var deck = two()
        XCTAssertEqual(deck.release(translation: SpringSwipe.threshold), .keep)
        XCTAssertEqual(deck.current?.name, "Newer")
        XCTAssertGreaterThan(SpringSwipe.rest(translation: SpringSwipe.threshold, width: 320), 320)
    }

    func testArrowDeleteAndReturnMapToChuckAndKeep() {
        XCTAssertEqual(SpringKeys.choice(keyCode: 123), .chuck)
        XCTAssertEqual(SpringKeys.choice(keyCode: 51), .chuck)
        XCTAssertEqual(SpringKeys.choice(keyCode: 117), .chuck)
        XCTAssertEqual(SpringKeys.choice(keyCode: 124), .keep)
        XCTAssertEqual(SpringKeys.choice(keyCode: 36), .keep)
        XCTAssertNil(SpringKeys.choice(keyCode: 53))
    }

    func testTheNextCardLiftsWhileTheFrontOneLeaves() {
        XCTAssertEqual(SpringFlight.scale(depth: 0, lift: 0), 1)
        XCTAssertEqual(SpringFlight.scale(depth: 1, lift: 0), SpringFlight.stackedScale)
        XCTAssertEqual(SpringFlight.peekOffset(depth: 1, lift: 0, peek: 16), 16)
        XCTAssertEqual(SpringFlight.scale(depth: 1, lift: 1), 1)
        XCTAssertEqual(SpringFlight.peekOffset(depth: 1, lift: 1, peek: 16), 0)
        XCTAssertGreaterThan(SpringFlight.scale(depth: 1, lift: 0.5), SpringFlight.stackedScale)
        XCTAssertLessThan(SpringFlight.peekOffset(depth: 1, lift: 0.5, peek: 16), 16)
    }

    func testRotationFollowsTheDragAndStaysCapped() {
        XCTAssertLessThan(SpringSwipe.rotation(translation: -80, width: 300), 0)
        XCTAssertGreaterThan(SpringSwipe.rotation(translation: 80, width: 300), 0)
        XCTAssertEqual(SpringSwipe.rotation(translation: 5000, width: 300), SpringSwipe.maxRotation)
        XCTAssertEqual(SpringSwipe.rotation(translation: -5000, width: 300), -SpringSwipe.maxRotation)
    }

    func testVideoCardsCarryTheirKindAndTheCommandIsHiddenFromMembers() throws {
        let clip = item(name: "Clip", added: "2020-01-01T00:00:00.000Z", opened: false, kind: "video", ext: "mp4")
        let cards = SpringDeck.rank(items: [("items/clip/item.json", clip)])
        let card = try XCTUnwrap(cards.first)
        XCTAssertEqual(card.kind, "video")
        XCTAssertEqual(card.ext, "mp4")
        XCTAssertTrue(SpringMedia.plays(card))
        XCTAssertEqual(SpringMedia.itemID(for: card.key), "clip")
        XCTAssertEqual(SpringMedia.fileName(ext: "mp4"), "original.mp4")
        XCTAssertFalse(SpringMedia.plays(UnopenedReference(key: "items/still/item.json", name: "Still", addedAt: 0, kind: "image", ext: "png")))
        XCTAssertEqual(SpringCommand.title, "Spring Cleaning")
        XCTAssertTrue(SpringCommand.visible(to: .owner))
        XCTAssertTrue(SpringCommand.visible(to: .admin))
        XCTAssertFalse(SpringCommand.visible(to: .member))
    }

    private func two() -> SpringDeck {
        let older = item(name: "Older", added: "2020-01-01T00:00:00.000Z", opened: false)
        let newer = item(name: "Newer", added: "2024-06-01T00:00:00Z", opened: false)
        return SpringDeck(cards: SpringDeck.rank(items: [
            ("items/new/item.json", newer),
            ("items/old/item.json", older),
        ]))
    }

    func testItemBodiesComeFromDiskAndOnlyMissingOnesAreLeftToFetch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grails-deck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("items/here/item.json")
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = item(name: "Here", added: "2020-01-01T00:00:00.000Z", opened: false)
        try body.write(to: local)
        let heads = [
            ObjectHead(key: "items/here/item.json", etag: "\"a\"", size: 1),
            ObjectHead(key: "items/away/item.json", etag: "\"b\"", size: 1),
            ObjectHead(key: "items/here/thumb.jpg", etag: "\"c\"", size: 1),
            ObjectHead(key: "library.json", etag: "\"d\"", size: 1),
        ]
        let read = SpringDeck.localItems(root: root, heads: heads)
        XCTAssertEqual(read.found.map(\.key), ["items/here/item.json"])
        XCTAssertEqual(read.found.first?.json, body)
        XCTAssertEqual(read.missing, ["items/away/item.json"])
        XCTAssertEqual(SpringDeck.localItems(root: nil, heads: heads).missing, ["items/here/item.json", "items/away/item.json"])
    }

    private func item(name: String, added: String, opened: Bool, deleted: Bool = false, kind: String? = nil, ext: String? = nil) -> Data {
        var object: [String: Any] = ["name": name, "addedAt": added]
        if let kind { object["kind"] = kind }
        if let ext { object["ext"] = ext }
        if opened { object["openedAt"] = "2025-01-01T00:00:00.000Z" }
        if deleted { object["deletedAt"] = "2025-02-01T00:00:00.000Z" }
        return try! JSONSerialization.data(withJSONObject: object)
    }
}
