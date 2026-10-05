import Foundation

/// How politely to treat each service: the least time between two reads from the same host.
public struct Politeness: Sendable {
    public var minimumGap: [String: Duration]
    public init(minimumGap: [String: Duration]) { self.minimumGap = minimumGap }
    public static let standard = Politeness(minimumGap: ["api.are.na": .seconds(1), "widgets.pinterest.com": .milliseconds(500)])
    public static let none = Politeness(minimumGap: [:])
}

/// Imports several boards in one go: boards in row order, each into its own collection, four downloads at a time across them, the
/// next board read while the current one downloads. A picture that two boards share is downloaded once and filed in both.
public actor ImportRunner {
    private let store: LibraryStore
    private let service: LibraryCaptureService
    private let loader: LinkFetcher.Loader
    private let politeness: Politeness
    private let journal: URL?
    private let concurrency: Int
    private var inputOpen: Bool
    private let rateLimitWait: Duration

    private var job: ImportJob
    private var stopped: Set<String> = []
    private var stopAll = false
    private var seen: [String: String] = [:]           // media URL → item id, across boards
    private var lastRead: [String: ContinuousClock.Instant] = [:]
    private var continuation: AsyncStream<ImportEvent>.Continuation?
    private var lastJournal = ContinuousClock.now
    private var sinceJournal = 0

    public init(job: ImportJob, store: LibraryStore, service: LibraryCaptureService, politeness: Politeness = .standard,
                loader: @escaping LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) }, journal: URL? = nil, concurrency: Int = 4, keepOpen: Bool = false, rateLimitWait: Duration = .seconds(60)) {
        self.rateLimitWait = rateLimitWait
        self.inputOpen = keepOpen
        self.job = job; self.store = store; self.service = service; self.politeness = politeness; self.loader = loader; self.journal = journal
        self.concurrency = max(1, concurrency)
    }

    public var current: ImportJob { job }

    public func stop(board id: String) { stopped.insert(id) }

    /// A board that turned up while the job was running (the browser extension finished scrolling one).
    public func append(_ task: BoardTask) {
        job.boards.append(task)
        emit(job.boards.count - 1)
    }

    /// No more boards are coming: the job ends when the ones it has are done.
    public func closeInput() { inputOpen = false }
    public func stopEverything() { stopAll = true }

    /// Runs the job. The stream ends when every board is done, failed, blocked or stopped.
    public nonisolated func events() -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            Task { await self.begin(continuation) }
        }
    }

    private func begin(_ c: AsyncStream<ImportEvent>.Continuation) async {
        continuation = c
        await run()
        writeJournal(force: true)
        c.yield(.finished(job))
        c.finish()
    }

    // MARK: The job

    private func run() async {
        var reads: [Int: Task<RemoteBoard, Error>] = [:]
        func read(_ i: Int) -> Task<RemoteBoard, Error> {
            if let t = reads[i] { return t }
            let candidate = job.boards[i].candidate
            let t = Task { try await self.readBoard(candidate, index: i) }
            reads[i] = t
            return t
        }
        var i = -1
        while true {
            i += 1
            if i >= job.boards.count {
                guard inputOpen, !stopAll else { break }
                i -= 1
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            let oneStopped = stopped.contains(job.boards[i].id)
            let skipThis = stopAll || oneStopped
            if skipThis { job.boards[i].state = .stopped; emit(i); continue }
            if case .done = job.boards[i].state { continue }
            let id = job.boards[i].id
            do {
                // entries kept from before (a resumed job) don't need reading again
                let entries: [RemoteBoard.Entry]
                var name = job.boards[i].candidate.name
                var ref = job.boards[i].candidate.ref
                if let kept = job.boards[i].entries { entries = kept } else {
                    set(i, .reading(found: 0, total: job.boards[i].candidate.count))
                    let board: RemoteBoard
                    do { board = try await read(i).value }
                    catch let e as BoardImportError {
                        // told to slow down: wait the minute out and try that board once more (a block is not retried)
                        guard case .blocked(let why) = e, why.localizedCaseInsensitiveContains("slow down") else { throw e }
                        set(i, .waiting(until: Date().addingTimeInterval(Double(rateLimitWait.components.seconds))))
                        try await Task.sleep(for: rateLimitWait)
                        reads[i] = nil
                        board = try await read(i).value
                    }
                    entries = board.entries
                    name = board.name
                    ref = board.ref
                    job.boards[i].entries = entries
                    job.boards[i].skipped = board.skipped
                    job.boards[i].note = board.note
                }
                // start reading the next board while this one downloads
                if i + 1 < job.boards.count, job.boards[i + 1].entries == nil, !stopAll { _ = read(i + 1) }
                job.boards[i].total = entries.count
                try await download(i, entries: entries, name: name, ref: ref)
            } catch let e as BoardImportError {
                switch e {
                case .blocked(let why): job.boards[i].state = .blocked(why)
                default: job.boards[i].state = .failed(e.errorDescription ?? "\(e)")
                }
                emit(i)
            } catch is CancellationError {
                job.boards[i].state = .stopped; emit(i)
            } catch {
                job.boards[i].state = .failed(error.localizedDescription); emit(i)
            }
            _ = id
        }
        for t in reads.values { t.cancel() }
    }

    private func readBoard(_ candidate: BoardCandidate, index: Int) async throws -> RemoteBoard {
        try await pause(for: host(of: candidate.ref))
        let importer = BoardImporter(loader: loader)
        let board = try await importer.fetch(candidate.ref) { found, total in
            Task { await self.reading(index, found: found, total: total) }
        }
        return board
    }

    private func reading(_ i: Int, found: Int, total: Int?) {
        guard job.boards.indices.contains(i), job.boards[i].entries == nil else { return }
        set(i, .reading(found: found, total: total ?? job.boards[i].candidate.count))
    }

    private func host(of ref: BoardRef) -> String {
        switch ref {
        case .arena: "api.are.na"
        case .pinterest, .pinterestPin: "widgets.pinterest.com"
        case .tweet: "cdn.syndication.twimg.com"
        }
    }

    /// Keeps reads from one host at least `minimumGap` apart.
    private func pause(for host: String) async throws {
        guard let gap = politeness.minimumGap[host] else { return }
        let now = ContinuousClock.now
        if let last = lastRead[host], last + gap > now { try await Task.sleep(until: last + gap, clock: .continuous) }
        lastRead[host] = ContinuousClock.now
    }

    // MARK: Downloading

    private enum Result { case added(String), had(String), failed }

    private func download(_ i: Int, entries: [RemoteBoard.Entry], name: String, ref: BoardRef) async throws {
        // a collection per board; a single post or pin lands loose
        if job.boards[i].collectionId == nil, !ref.isPost {
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let wanted = title.isEmpty ? ref.service : title
            let existing = try await store.index.collections().first { !$0.archived && $0.parentId == nil && $0.kind == "collection" && $0.name.lowercased() == wanted.lowercased() }
            if let existing { job.boards[i].collectionId = existing.id } else { job.boards[i].collectionId = try await store.createCollection(name: wanted).id }
        }
        let collectionId = job.boards[i].collectionId
        let tags = job.tags
        let store = self.store, service = self.service
        let total = entries.count
        set(i, .downloading(done: job.boards[i].handled.count, total: total))
        let boardID = job.boards[i].id

        var next = 0
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var active = 0
            func launchMore() {
                while active < concurrency, next < entries.count {
                    let index = next; next += 1
                    if job.boards[i].handled.contains(index) { continue }
                    let entry = entries[index]
                    let one = stopped.contains(boardID)
        let stoppedNow = stopAll || one
                    if stoppedNow { return }
                    // a picture an earlier board already brought in is filed here too, not downloaded again
                    if let key = entry.mediaUrls.first, let known = seen[key] {
                        active += 1
                        group.addTask { await Self.file(known, in: collectionId, store: store); return (index, .had(known)) }
                        continue
                    }
                    active += 1
                    group.addTask { (index, await Self.save(entry, collectionId: collectionId, tags: tags, store: store, service: service)) }
                }
            }
            launchMore()
            while let (index, result) = try await group.next() {
                active -= 1
                job.boards[i].handled.insert(index)
                switch result {
                case .added(let id):
                    job.boards[i].added += 1; job.boards[i].addedIDs.append(id)
                    if let key = entries[index].mediaUrls.first { seen[key] = id }
                    continuation?.yield(.itemAdded(board: job.boards[i].id, item: id))
                case .had(let id):
                    job.boards[i].alreadyHad += 1
                    if let key = entries[index].mediaUrls.first { seen[key] = id }
                case .failed: job.boards[i].failed += 1
                }
                set(i, .downloading(done: job.boards[i].handled.count, total: total))
                sinceJournal += 1
                writeJournal(force: false)
                launchMore()
            }
        }
        let one = stopped.contains(boardID)
        let stoppedNow = stopAll || one
        job.boards[i].state = stoppedNow ? .stopped : .done
        emit(i)
    }

    private static func file(_ id: String, in collectionId: String?, store: LibraryStore) async {
        if let collectionId { try? await store.add(ids: [id], toCollection: collectionId) }
    }

    /// Files: the first URL that downloads wins. Links (no file URL) become link cards.
    private static func save(_ e: RemoteBoard.Entry, collectionId: String?, tags: [String], store: LibraryStore, service: LibraryCaptureService) async -> Result {
        let attempts: [SaveRequest] = e.mediaUrls.isEmpty
            ? [SaveRequest(pageUrl: e.pageUrl, title: e.title, collectionId: collectionId, tags: tags, author: e.author)]
            : e.mediaUrls.map { SaveRequest(mediaUrl: $0, pageUrl: e.pageUrl, title: e.title, collectionId: collectionId, tags: tags, author: e.author) }
        for request in attempts {
            if Task.isCancelled { return .failed }
            guard let result = try? await service.save(request) else { continue }
            if result.duplicate {
                await file(result.id, in: collectionId, store: store)
                return .had(result.id)
            }
            return .added(result.id)
        }
        return .failed
    }

    // MARK: Events and the journal

    private func set(_ i: Int, _ state: BoardState) { job.boards[i].state = state; emit(i) }
    private func emit(_ i: Int) { continuation?.yield(.updated(job.boards[i])) }

    private func writeJournal(force: Bool) {
        guard let journal else { return }
        let now = ContinuousClock.now
        guard force || sinceJournal >= 50 || lastJournal + .seconds(2) <= now else { return }
        sinceJournal = 0; lastJournal = now
        if let data = try? JSONEncoder().encode(job) {
            try? FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: journal, options: .atomic)
        }
    }
}

/// Jobs that were interrupted, found again on launch.
public enum ImportJournal {
    public static func directory(libraryId: String, in support: URL) -> URL {
        support.appendingPathComponent("Imports", isDirectory: true).appendingPathComponent(libraryId, isDirectory: true)
    }

    public static func fileURL(for job: ImportJob, in support: URL) -> URL {
        directory(libraryId: job.libraryId, in: support).appendingPathComponent("\(job.id.uuidString).json")
    }

    /// Unfinished jobs for this library, oldest first.
    public static func unfinished(libraryId: String, in support: URL) -> [ImportJob] {
        let dir = directory(libraryId: libraryId, in: support)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? JSONDecoder().decode(ImportJob.self, from: Data(contentsOf: $0)) }.filter(\.needsWork)
    }

    public static func remove(_ job: ImportJob, in support: URL) { try? FileManager.default.removeItem(at: fileURL(for: job, in: support)) }
}
