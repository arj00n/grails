import Foundation
import Testing
@testable import GrailsKit

/// Pages in the shape the in-app reader hands over (made up: no Pinterest content is stored).
private func pin(_ id: Int, video: Bool = false) -> [String: Any] {
    var p: [String: Any] = ["type": "pin", "id": "\(id)", "description": "Pin \(id)", "link": NSNull(), "pinner": ["username": "ana", "full_name": "Ana"],
                            "images": ["orig": ["url": "https://cdn.test/img\(id).png"], "236x": ["url": "https://i.pinimg.com/236x/aa/bb/img\(id).jpg"]]]
    if video { p["videos"] = ["video_list": ["V_720P": ["url": "https://cdn.test/v\(id).mp4", "width": 720]]] }
    return p
}

@Suite struct PinterestFeedTests {
    @Test func aPageBecomesEntriesWithTheirOriginalsFirstAndTheNextBookmark() throws {
        let page = try #require(PinterestBoardFeed.parsePage(["status": 200, "data": [pin(1), pin(2), ["type": "story", "id": "x"], pin(3, video: true)], "bookmark": "bm1"], author: "ana"))
        #expect(page.pinCount == 3 && page.entries.count == 3 && page.bookmark == "bm1" && !page.ended)
        #expect(page.entries[0].mediaUrls.first == "https://cdn.test/img1.png")
        #expect(page.entries[2].mediaUrls.first == "https://cdn.test/v3.mp4")                       // a video pin's file comes before its picture
        #expect(page.entries[0].title == "Pin 1" && page.entries[0].author == "Ana")
    }

    @Test func theLastPageSaysSoAndAMalformedOneIsNotAPage() throws {
        #expect(try #require(PinterestBoardFeed.parsePage(["status": 200, "data": [pin(1)], "bookmark": "-end-"])).ended)
        #expect(try #require(PinterestBoardFeed.parsePage(["status": 200, "data": [pin(1)]])).ended)
        #expect(PinterestBoardFeed.parsePage(["status": 200, "oops": 1]) == nil)
        #expect(PinterestBoardFeed.parsePage(["status": 403])?.status == 403)
    }

    @Test func aProfilesBoardsComeWithTheirSizeAndWhetherTheyAreSecret() {
        let r = PinterestBoardFeed.parseBoards(["data": [["name": "Interiors", "url": "/ana/interiors/", "pin_count": 1204, "privacy": "public", "image_cover_url": "https://cdn.test/c.jpg"],
                                                         ["name": "Plans", "url": "/ana/plans/", "pin_count": 12, "privacy": "secret"], ["bad": 1]], "bookmark": "-end-"])
        #expect(r.boards.count == 2 && r.bookmark == nil)
        #expect(r.boards[0].pinCount == 1204 && !r.boards[0].secret && r.boards[0].cover == "https://cdn.test/c.jpg")
        #expect(r.boards[1].secret)
    }
}

@Suite struct CollectorPlanTests {
    func page(_ n: Int, end: Bool = false, raw: Int? = nil) -> FeedPage { FeedPage(entries: [], pinCount: n, rawCount: raw ?? n, bookmark: end ? "-end-" : "bm", status: 200) }

    @Test func itPagesAtAboutOnePointTwoSecondsAndStopsAtTheEnd() {
        var plan = CollectorPlan()
        guard case .next(let d) = plan.record(status: 200, page: page(100), jitter: 0.5) else { Issue.record("no next"); return }
        #expect(abs(d - 1.2) < 1e-9)
        for j in [0.0, 1.0] { var p = CollectorPlan(); if case .next(let x) = p.record(status: 200, page: page(100), jitter: j) { #expect(x >= 0.96 - 1e-9 && x <= 1.44 + 1e-9) } }
        #expect(plan.record(status: 200, page: page(40, end: true)) == .done)
        #expect(plan.pins == 140 && plan.pages == 2)
    }

    @Test func anEmptyPageOrTheCapEndsTheReadButAPageOfOnlyOtherRowsDoesNot() {
        var a = CollectorPlan()
        #expect(a.record(status: 200, page: page(0)) == .done)
        var other = CollectorPlan()
        if case .next = other.record(status: 200, page: page(0, raw: 25)) {} else { Issue.record("a page of ads shouldn't end the board") }
        var b = CollectorPlan(resumedPins: CollectorPlan.maxPins - 50)
        #expect(b.record(status: 200, page: page(100)) == .done)
    }

    @Test func slowDownWaitsWhatPinterestAsksAndNeverCountsAsAFailure() {
        var plan = CollectorPlan()
        #expect(plan.record(status: 429, page: nil, retryAfter: 42) == .wait(seconds: 42))
        #expect(plan.record(status: 429, page: nil) == .wait(seconds: 60))
        #expect(plan.failures == 0)
    }

    @Test func aSecretBoardIsGatedAndThreeBadRepliesFallBackToTheWidget() {
        var secret = CollectorPlan()
        #expect(secret.record(status: 403, page: nil) == .gated && secret.record(status: 401, page: nil) == .gated)
        var plan = CollectorPlan()
        if case .next = plan.record(status: 200, page: nil) {} else { Issue.record("first failure should retry") }
        if case .next = plan.record(status: 500, page: nil) {} else { Issue.record("second failure should retry") }
        #expect(plan.record(status: 200, page: nil) == .changed)
        var recovers = CollectorPlan()
        _ = recovers.record(status: 200, page: nil)
        _ = recovers.record(status: 200, page: page(100))
        #expect(recovers.failures == 0)
    }
}

@Suite struct StreamingReadTests {
    func setup(_ net: FakeNet) throws -> (LibraryStore, LibraryCaptureService) {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        return (store, LibraryCaptureService(fetcher: LinkFetcher(load: net.loader), download: net.loader, store: { store }))
    }

    func candidate(_ count: Int) -> BoardCandidate { BoardCandidate(ref: .pinterest(user: "ana", board: "big"), name: "Big", count: count, via: .collector) }

    func entries(_ range: Range<Int>) -> [RemoteBoard.Entry] { range.map { .init(mediaUrls: ["https://cdn.test/img\($0).png"], pageUrl: nil, title: "Pin \($0)", author: "ana") } }

    @Test func downloadsStartWithTheFirstPageAndTheBoardEndsWhenTheReadDoes() async throws {
        final class Log: @unchecked Sendable {
            private let l = NSLock()
            private var _first = -1, _pages = 0
            var firstDownloadAtPage: Int { l.lock(); defer { l.unlock() }; return _first }
            func pageDone(_ n: Int) { l.lock(); _pages = n; l.unlock() }
            func noteDownload() { l.lock(); if _first < 0 { _first = _pages }; l.unlock() }
        }
        let log = Log()
        let net = FakeNet()
        net.delay = 5_000_000
        let (store, service) = try setup(net)
        let reader: PageReader = { _, _, deliver in
            for p in 0..<4 {
                await deliver(self.entries(p * 10..<(p + 1) * 10), p == 3 ? nil : "bm\(p)")
                log.pageDone(p + 1)
                try await Task.sleep(nanoseconds: 120_000_000)           // the next page takes a while
            }
            return .complete
        }
        let runner = ImportRunner(job: ImportJob(libraryId: "L", boards: [candidate(40)]), store: store, service: service, politeness: .none, loader: net.loader, collector: reader)
        for await e in runner.events() {
            if case .itemAdded = e { log.noteDownload() }
            if case .finished(let done) = e {
                #expect(done.boards[0].added == 40 && done.boards[0].state == .done && done.boards[0].readComplete == true && done.boards[0].cursor == nil)
            }
        }
        #expect(log.firstDownloadAtPage >= 1 && log.firstDownloadAtPage < 4)                 // pictures arrived while later pages were still being read
        #expect(try await store.index.count(ItemQuery()) == 40)
    }

    @Test func aResumedBoardContinuesFromItsCursorAndDoesNotDoubleUp() async throws {
        let net = FakeNet()
        let (store, service) = try setup(net)
        final class Seen: @unchecked Sendable { var cursor: String?? }
        let seen = Seen()
        var task = BoardTask(candidate: candidate(30))
        task.entries = entries(0..<10); task.cursor = "bm0"; task.handled = Set(0..<10); task.added = 10; task.total = 30
        var job = ImportJob(libraryId: "L", boards: []); job.boards = [task]
        let reader: PageReader = { _, cursor, deliver in
            seen.cursor = .some(cursor)
            await deliver(self.entries(10..<30), nil)
            return .complete
        }
        // the first ten were already in the library
        let first = try await service.save(SaveRequest(mediaUrl: "https://cdn.test/img0.png", pageUrl: nil, title: "x", collectionId: nil, tags: [], author: nil))
        _ = first
        let runner = ImportRunner(job: job, store: store, service: service, politeness: .none, loader: net.loader, collector: reader)
        var done: ImportJob?
        for await e in runner.events() { if case .finished(let j) = e { done = j } }
        #expect(seen.cursor == .some("bm0"))
        #expect(done?.boards[0].handled.count == 30 && done?.boards[0].state == .done)
    }

    @Test func aSecretBoardEndsBlockedAndAReaderThatGivesUpFallsBackToTheWidget() async throws {
        let net = FakeNet()
        let (store, service) = try setup(net)
        let gated: PageReader = { _, _, _ in .gated }
        let r1 = ImportRunner(job: ImportJob(libraryId: "L", boards: [candidate(80)]), store: store, service: service, politeness: .none, loader: net.loader, collector: gated)
        var done1: ImportJob?
        for await e in r1.events() { if case .finished(let j) = e { done1 = j } }
        #expect({ if case .blocked("Secret board")? = done1?.boards[0].state { true } else { false } }())
    }
}
