import Foundation
import Testing
@testable import GrailsKit

/// A stubbed network for Are.na channels and their pictures, counting how many downloads are in flight at once.
final class FakeNet: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var peak = 0
    private(set) var downloads: [String] = []
    var channels: [String: [Int]] = [:]            // slug → image ids
    var blocked: Set<String> = []
    var delay: UInt64 = 20_000_000
    private var pngs: [String: Data] = [:]
    private let dir = TestSupport.tempDir()

    func png(_ key: String) -> Data {
        lock.lock(); defer { lock.unlock() }
        if let d = pngs[key] { return d }
        var h = 7; for u in key.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0xFFFFFF }
        let d = (try? Data(contentsOf: TestSupport.makePNG(in: dir, name: "p\(pngs.count)", rgb: (Double(h & 255) / 255, Double((h >> 8) & 255) / 255, Double((h >> 16) & 255) / 255)))) ?? Data()
        pngs[key] = d
        return d
    }

    private func enter(_ url: String) { lock.lock(); inFlight += 1; peak = max(peak, inFlight); downloads.append(url); lock.unlock() }
    private func leave() { lock.lock(); inFlight -= 1; lock.unlock() }

    var loader: LinkFetcher.Loader {
        { req in
            let url = req.url!
            func ok(_ d: Data, _ type: String = "application/json") -> (Data, URLResponse) { (d, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!) }
            if url.host == "api.are.na" {
                let slug = url.lastPathComponent
                if self.blocked.contains(slug) { return (Data("403 - Automated access blocked".utf8), HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!) }
                guard let ids = self.channels[slug] else { return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!) }
                let blocks: [[String: Any]] = ids.map { ["id": $0, "class": "Image", "title": "Image \($0)", "user": ["slug": "ana"], "image": ["original": ["url": "https://cdn.test/img\($0).png"]]] }
                return ok(try JSONSerialization.data(withJSONObject: ["title": slug.capitalized, "length": ids.count, "contents": blocks]))
            }
            if url.host == "cdn.test" {
                self.enter(url.absoluteString)
                try await Task.sleep(nanoseconds: self.delay)
                self.leave()
                return ok(self.png(url.absoluteString), "image/png")
            }
            return ok(Data("<html></html>".utf8), "text/html")
        }
    }
}

@Suite struct ImportRunnerTests {
    func setup(_ net: FakeNet) throws -> (LibraryStore, LibraryCaptureService) {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: net.loader), download: net.loader, store: { store })
        return (store, service)
    }

    func job(_ slugs: [String], library: String) -> ImportJob {
        ImportJob(libraryId: library, boards: slugs.map { BoardCandidate(ref: .arena(slug: $0), name: $0.capitalized, count: nil) })
    }

    func collect(_ runner: ImportRunner, onEvent: (@Sendable (ImportEvent) -> Void)? = nil) async -> [ImportEvent] {
        var all: [ImportEvent] = []
        for await e in runner.events() { all.append(e); onEvent?(e) }
        return all
    }

    @Test func boardsRunInOrderEachInItsOwnCollectionWithAtMostFourDownloadsAtOnce() async throws {
        let net = FakeNet()
        net.channels = ["alpha": [1, 2, 3, 4, 5, 6], "beta": [7, 8, 9], "gamma": [10, 11]]
        let (store, service) = try setup(net)
        let runner = ImportRunner(job: job(["alpha", "beta", "gamma"], library: "L"), store: store, service: service, politeness: .none, loader: net.loader)
        let events = await collect(runner)
        guard case .finished(let done)? = events.last else { Issue.record("no finish"); return }
        #expect(done.boards.map(\.added) == [6, 3, 2] && done.isFinished)
        #expect(done.boards.allSatisfy { $0.state == .done })
        #expect(net.peak <= 4 && net.peak >= 2)
        let names = try await store.index.collections().map(\.name)
        #expect(Set(names) == ["Alpha", "Beta", "Gamma"])
        // the first board finished before the last one started downloading
        let doneAlpha = events.firstIndex { if case .updated(let t) = $0, t.id == "arena:alpha", t.state == .done { true } else { false } }
        let firstGamma = events.firstIndex { if case .updated(let t) = $0, t.id == "arena:gamma", case .downloading = t.state { true } else { false } }
        #expect(try #require(doneAlpha) < #require(firstGamma))
        #expect(events.filter { if case .itemAdded = $0 { true } else { false } }.count == 11)
    }

    @Test func aPictureTwoBoardsShareIsDownloadedOnceAndFiledInBoth() async throws {
        let net = FakeNet()
        net.channels = ["one": [1, 2, 3], "two": [3, 4]]
        let (store, service) = try setup(net)
        let runner = ImportRunner(job: job(["one", "two"], library: "L"), store: store, service: service, politeness: .none, loader: net.loader)
        let events = await collect(runner)
        guard case .finished(let done)? = events.last else { return }
        #expect(done.boards[0].added == 3 && done.boards[1].added == 1 && done.boards[1].alreadyHad == 1)
        #expect(net.downloads.filter { $0.hasSuffix("img3.png") }.count == 1)
        #expect(try await store.index.count(ItemQuery()) == 4)
        let two = try #require(try await store.index.collections().first { $0.name == "Two" })
        var q = ItemQuery(); q.collectionId = two.id
        #expect(try await store.index.count(q) == 2)                       // its own picture and the shared one
    }

    @Test func aBlockedServiceStopsThatBoardOnlyAndAStoppedBoardStaysStopped() async throws {
        let net = FakeNet()
        net.channels = ["ok": [1, 2], "walled": [3], "later": [4]]
        net.blocked = ["walled"]
        let (store, service) = try setup(net)
        let runner = ImportRunner(job: job(["ok", "walled", "later"], library: "L"), store: store, service: service, politeness: .none, loader: net.loader)
        await runner.stop(board: "arena:later")
        let events = await collect(runner)
        guard case .finished(let done)? = events.last else { return }
        #expect(done.boards[0].state == .done && done.boards[0].added == 2)
        if case .blocked = done.boards[1].state {} else { Issue.record("expected blocked, got \(done.boards[1].state)") }
        #expect(done.boards[2].state == .stopped && done.boards[2].added == 0)
        #expect(RowPresenter.row(done.boards[1]).action == .retry)
        #expect(RowPresenter.row(done.boards[2]).action == .resume)
    }

    @Test func aQuitMidwayResumesFromTheJournalToTheSameCountsWithoutDoubles() async throws {
        let net = FakeNet()
        net.channels = ["big": Array(1...12), "small": [20, 21, 22]]
        let (store, service) = try setup(net)
        let support = TestSupport.tempDir()
        var j = job(["big", "small"], library: "L")
        let file = ImportJournal.fileURL(for: j, in: support)
        let first = ImportRunner(job: j, store: store, service: service, politeness: .none, loader: net.loader, journal: file, concurrency: 2)
        // stop everything once five pictures have arrived
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        _ = await collect(first) { e in
            if case .itemAdded = e { count.n += 1; if count.n == 5 { Task { await first.stopEverything() } } }
        }
        let partial = ImportJournal.unfinished(libraryId: "L", in: support)
        #expect(partial.count == 1)
        j = try #require(partial.first)
        #expect(j.boards[0].entries?.count == 12 && j.boards[0].handled.count < 12)
        // relaunch: every unfinished board goes back to queued and carries on where it was
        for i in j.boards.indices where j.boards[i].state == .stopped { j.boards[i].state = .queued }
        let second = ImportRunner(job: j, store: store, service: service, politeness: .none, loader: net.loader, journal: file, concurrency: 2)
        let events = await collect(second)
        guard case .finished(let done)? = events.last else { return }
        #expect(done.boards.allSatisfy { $0.state == .done })
        #expect(done.boards[0].added + done.boards[0].alreadyHad == 12 && done.boards[1].added == 3)
        #expect(try await store.index.count(ItemQuery()) == 15)           // nothing twice
        #expect(Set(net.downloads).count == net.downloads.count)           // and nothing downloaded twice
    }

    @Test func rowsSayWhatIsHappeningInFewWords() {
        var t = BoardTask(candidate: BoardCandidate(ref: .arena(slug: "a"), name: "A", count: 9))
        #expect(RowPresenter.row(t) == ("Queued", nil, .remove))
        t.state = .reading(found: 300, total: 1204); #expect(RowPresenter.row(t).label == "Reading 300/1,204")
        t.state = .downloading(done: 412, total: 1204); #expect(RowPresenter.row(t) == ("412/1,204", nil, .stop))
        t.state = .waiting(until: Date().addingTimeInterval(42)); #expect(RowPresenter.row(t).label.hasPrefix("Waiting 0:"))
        t.added = 30; t.alreadyHad = 2; t.skipped = ["text blocks": 4]; t.state = .done
        #expect(RowPresenter.row(t) == ("32 ✓", "4 text blocks", nil))
        t.state = .failed("Couldn't reach the site"); #expect(RowPresenter.row(t) == ("Failed", "Couldn't reach the site", .retry))
        for state: BoardState in [.queued, .stopped, .done] { #expect(RowPresenter.row({ var x = t; x.state = state; return x }()).label.split(separator: " ").count <= 4) }
    }
}

@Suite struct ImportRunnerAppendTests {
    @Test func aBoardThatArrivesWhileTheJobRunsIsImportedBeforeItEnds() async throws {
        let net = FakeNet()
        net.channels = ["first": [1, 2]]
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: net.loader), download: net.loader, store: { store })
        let job = ImportJob(libraryId: "L", boards: [BoardCandidate(ref: .arena(slug: "first"), name: "First")])
        let runner = ImportRunner(job: job, store: store, service: service, politeness: .none, loader: net.loader, keepOpen: true)
        // a board the browser scrolled: its entries come with it, nothing is read from the network
        var late = BoardTask(candidate: BoardCandidate(ref: .pinterest(user: "ana", board: "full"), name: "Full"))
        late.entries = (10...13).map { .init(mediaUrls: ["https://cdn.test/img\($0).png"], pageUrl: "https://www.pinterest.com/pin/\($0)/", title: "Pin \($0)", author: nil) }
        Task { try? await Task.sleep(for: .milliseconds(150)); await runner.append(late); await runner.closeInput() }
        var finished: ImportJob?
        for await e in runner.events() { if case .finished(let j) = e { finished = j } }
        let done = try #require(finished)
        #expect(done.boards.count == 2 && done.boards.allSatisfy { $0.state == .done })
        #expect(done.boards[0].added == 2 && done.boards[1].added == 4)
        #expect(try await store.index.count(ItemQuery()) == 6)
    }
}

@Suite struct ImportRunnerPolitenessTests {
    @Test func aBoardTheServiceTellsUsToSlowDownForIsWaitedOutAndRetriedOnce() async throws {
        final class Hits: @unchecked Sendable { var n = 0; let lock = NSLock(); func hit() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n } }
        let hits = Hits()
        let net = FakeNet()
        net.channels = ["calm": [1, 2]]
        let inner = net.loader
        let loader: LinkFetcher.Loader = { req in
            if req.url?.host == "api.are.na", hits.hit() == 1 { return (Data(), HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!) }
            return try await inner(req)
        }
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
        let job = ImportJob(libraryId: "L", boards: [BoardCandidate(ref: .arena(slug: "calm"), name: "Calm")])
        let runner = ImportRunner(job: job, store: store, service: service, politeness: .none, loader: loader, rateLimitWait: .milliseconds(50))
        var sawWaiting = false
        var finished: ImportJob?
        for await e in runner.events() {
            if case .updated(let t) = e, case .waiting = t.state { sawWaiting = true }
            if case .finished(let j) = e { finished = j }
        }
        #expect(sawWaiting)
        #expect(finished?.boards[0].state == .done && finished?.boards[0].added == 2)
    }
}
