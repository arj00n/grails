import Foundation
import Testing
@testable import GrailsKit

@Suite struct LinkHarvesterTests {
    @Test func findsBoardsInAnyTextInOrderWithoutRepeats() {
        let text = """
        my boards: https://www.are.na/ana/typography-in-use, pinterest.com/ana/interiors/ and again https://www.are.na/ana/typography-in-use.
        Slack: <https://x.com/studio/status/123|a post> and https://pin.it/3zWlMd642!
        """
        let found = LinkHarvester.harvest(text)
        #expect(found == [
            .board(.arena(slug: "typography-in-use")), .board(.pinterest(user: "ana", board: "interiors")),
            .board(.tweet(id: "123", user: "studio")), .pinterestShort(URL(string: "https://pin.it/3zWlMd642")!),
        ])
    }

    @Test func recognisesPeopleAndPins() {
        #expect(LinkHarvester.harvest("https://www.are.na/charles-broskoski") == [.arenaUser(slug: "charles-broskoski")])
        #expect(LinkHarvester.harvest("pinterest.com/ana") == [.pinterestUser(user: "ana")])
        #expect(LinkHarvester.harvest("https://www.pinterest.com/ana/_saved/") == [.pinterestUser(user: "ana")])
        #expect(LinkHarvester.harvest("https://www.pinterest.com/pin/123456/") == [.board(.pinterestPin(id: "123456"))])
        #expect(LinkHarvester.harvest("https://www.are.na/channels/arena-influences") == [.board(.arena(slug: "arena-influences"))])
    }

    @Test func otherLinksAreFlaggedAndPlainWordsIgnored() {
        #expect(LinkHarvester.harvest("hello there, nothing to see") == [])
        #expect(LinkHarvester.harvest("https://example.com/boards/1") == [.unrecognised("https://example.com/boards/1")])
        #expect(LinkHarvester.harvest("https://www.are.na/block/123") == [.unrecognised("https://www.are.na/block/123")])
    }
}

@Suite struct ArenaDirectoryTests {
    static func response(_ url: URL, _ code: Int = 200) -> URLResponse { HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)! }

    static func channel(_ slug: String, owner: String, contents: Int, visibility: String = "public") -> [String: Any] {
        ["slug": slug, "title": slug.capitalized, "visibility": visibility, "owner": ["slug": owner], "counts": ["contents": contents]]
    }

    @Test func ownedChannelsComeFirstAndTickedOthersFollowUnticked() async throws {
        let pages: [Int: [String: Any]] = [
            1: ["meta": ["has_more_pages": true], "data": [Self.channel("others-one", owner: "mira", contents: 30), Self.channel("mine-a", owner: "ana", contents: 5), Self.channel("secret", owner: "ana", contents: 2, visibility: "private")]],
            2: ["meta": ["has_more_pages": false], "data": [Self.channel("mine-b", owner: "ana", contents: 23)]],
        ]
        let data = pages.mapValues { try! JSONSerialization.data(withJSONObject: $0) }
        var dir = ArenaDirectory(loader: { req in
            let page = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
            #expect(req.url!.path == "/v3/users/ana/contents")
            return (data[page] ?? Data(), Self.response(req.url!))
        })
        dir.pause = .zero
        let list = try await dir.channels(user: "ana")
        #expect(list.map(\.id) == ["arena:mine-a", "arena:mine-b", "arena:others-one"])
        #expect(list.map(\.selected) == [true, true, false])
        #expect(list[2].owner == "mira" && list[0].owner == nil)
        #expect(list.map(\.count) == [5, 23, 30])
    }

    @Test func blockedAndMissingAreSaidPlainly() async {
        var missing = ArenaDirectory(loader: { req in (Data(), Self.response(req.url!, 404)) }); missing.pause = .zero
        await #expect(throws: BoardImportError.self) { _ = try await missing.channels(user: "nobody") }
        var slow = ArenaDirectory(loader: { req in (Data(), Self.response(req.url!, 429)) }); slow.pause = .zero
        await #expect(throws: BoardImportError.self) { _ = try await slow.channels(user: "ana") }
    }
}

@Suite struct PinterestWidgetTests {
    static func boardJSON(count: Int, pins: Int) -> Data {
        let list: [[String: Any]] = (0..<pins).map { i in
            ["id": "\(1000 + i)", "description": "Pin \(i)", "images": ["236x": ["url": "https://i.pinimg.com/236x/aa/bb/cc/p\(i).jpg"]]]
        }
        return try! JSONSerialization.data(withJSONObject: ["status": "success", "data": ["board": ["name": "Interiors", "pin_count": count], "pins": list]])
    }

    @Test func aBoardReadsItsLatestPinsAndKnowsTheTotal() async throws {
        let loader: LinkFetcher.Loader = { req in
            #expect(req.url!.absoluteString.contains("/v3/pidgets/boards/ana/interiors/pins/"))
            return (Self.boardJSON(count: 1204, pins: 50), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let board = try await BoardImporter(loader: loader).fetch(.pinterest(user: "ana", board: "interiors"))
        #expect(board.name == "Interiors" && board.entries.count == 50 && board.expectedTotal == 1204)
        #expect(board.note == "Latest 50 of 1204")
        let c = try await BoardPreflight.check(.pinterest(user: "ana", board: "interiors"), loader: loader)
        #expect(c.count == 1204 && c.via == .collector && c.covers.count == 3 && c.name == "Interiors")
    }

    @Test func aSmallBoardIsWholeAndAMissingOneIsSaid() async throws {
        let small: LinkFetcher.Loader = { req in (Self.boardJSON(count: 12, pins: 12), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        #expect(try await BoardPreflight.check(.pinterest(user: "a", board: "b"), loader: small).via == .api)
        let gone: LinkFetcher.Loader = { req in (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!) }
        await #expect(throws: BoardImportError.self) { _ = try await BoardPreflight.check(.pinterest(user: "a", board: "b"), loader: gone) }
    }
}

@Suite struct PinterestFallbackTests {
    @Test func pinsThePageShowedButTheWidgetDoesntKnowStillImportThroughTheirPicture() async throws {
        let loader: LinkFetcher.Loader = { req in (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        let board = try await BoardImporter(loader: loader).fetchPinterestPins(
            ids: ["AbC123", "999"], ref: .pinterest(user: "ana", board: "x"), name: "X", author: "ana",
            images: ["AbC123": "https://i.pinimg.com/236x/aa/bb/cc/one.jpg", "999": "https://i.pinimg.com/236x/dd/ee/ff/two.jpg"])
        #expect(board.entries.count == 2)                                                              // neither is skipped
        #expect(board.entries[0].mediaUrls.first == "https://i.pinimg.com/originals/aa/bb/cc/one.jpg")
        #expect(board.entries[0].pageUrl == "https://www.pinterest.com/pin/AbC123/")
        #expect(board.skipped.isEmpty)
        // without a picture they are skipped, and said so
        await #expect(throws: BoardImportError.self) {
            _ = try await BoardImporter(loader: loader).fetchPinterestPins(ids: ["zzz"], ref: .pinterest(user: "a", board: "b"), name: "x", author: nil)
        }
    }
}


@Suite struct BrowserSuppliedPinsTests {
    final class Count: @unchecked Sendable { private let l = NSLock(); private var n = 0; func hit() { l.lock(); n += 1; l.unlock() }; var value: Int { l.lock(); defer { l.unlock() }; return n } }

    @Test func pinsTheBrowserGavePicturesForNeverCostAWidgetLookupSoABigBoardCantBeSlowedDownOut() async throws {
        let count = Count()
        let loader: LinkFetcher.Loader = { req in
            count.hit()
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)     // the widget would say "slow down"
        }
        var images: [String: String] = [:]
        let ids = (0..<95).map { String(7000 + $0) }
        for id in ids { images[id] = "https://i.pinimg.com/originals/aa/bb/\(id).jpg" }
        let r = try await PinterestPins.resolve(ids: ids, authorFallback: "ana", images: images, loader: loader)
        #expect(count.value == 0 && r.entries.count == 95 && r.skipped.isEmpty)
        #expect(r.entries[0].mediaUrls.first == "https://i.pinimg.com/originals/aa/bb/7000.jpg")
    }
}
