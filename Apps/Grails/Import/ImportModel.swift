import AppKit
import GrailsKit
import SwiftUI

/// The import flow, shared by the ⇧⌘I panel and onboarding: links go in, rows come out (each a board, with its name, size and pictures),
/// the ticked ones run as one job, and the rows turn into progress.
@MainActor @Observable
final class ImportModel {
    enum Phase: Equatable { case composing, running, finished }
    enum Status: Equatable { case checking, ready, expanding, needsBrowser, rejected(String), blocked(String), offline }

    struct Row: Identifiable, Equatable {
        var id: String
        var candidate: LinkCandidate
        var status: Status
        /// The board itself, once known (not set for people, whose boards are `children`).
        var board: BoardCandidate?
        var children: [BoardCandidate] = []
        /// What the row calls itself before it is known.
        var title: String
    }

    private(set) var rows: [Row] = []
    private(set) var phase: Phase = .composing
    private(set) var tasks: [String: BoardTask] = [:]
    private(set) var order: [String] = []
    /// Item ids as they arrive, newest last: the collage draws from these.
    private(set) var arrivals: [String] = []
    private(set) var arrivedCount = 0
    private(set) var finishedJob: ImportJob?
    /// After a job: open the first board's collection (onboarding does).
    var opensFirstCollection = false

    weak var app: AppModel?
    @ObservationIgnored private var runner: ImportRunner?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private var checking = 0
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored var loader: LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) }
    /// Dev demos: reads and downloads both go through `loader`.
    @ObservationIgnored var fixtureNetwork = false

    var isRunning: Bool { phase == .running }

    /// Pinterest is in the list and would do better with the extension: show it.
    var wantsExtension: Bool {
        phase == .composing && rows.contains { r in
            if case .pinterestUser = r.candidate { return true }
            return r.board?.via == .latest || r.board?.via == .browser || r.children.contains { $0.via == .browser }
        }
    }

    // MARK: Composing

    /// Adds every link found in `text` as a row (links already there are left alone).
    func ingest(_ text: String) {
        guard phase != .running else { return }
        if phase == .finished { reset() }
        for c in LinkHarvester.harvest(text) { add(c) }
    }

    private func key(_ c: LinkCandidate) -> String {
        switch c {
        case .board(let ref): BoardCandidate.id(for: ref)
        case .arenaUser(let s): "arena-user:\(s)"
        case .pinterestUser(let u): "pinterest-user:\(u)"
        case .pinterestShort(let url): "short:\(url.absoluteString)"
        case .unrecognised(let s): "other:\(s)"
        }
    }

    private func add(_ c: LinkCandidate) {
        let id = key(c)
        guard !rows.contains(where: { $0.id == id }) else { return }
        switch c {
        case .board(let ref):
            rows.append(Row(id: id, candidate: c, status: .checking, title: ref.webURL.host ?? "Link"))
            enqueue(id)
        case .arenaUser(let slug):
            rows.append(Row(id: id, candidate: c, status: .expanding, title: slug))
            enqueue(id)
        case .pinterestUser(let user):
            rows.append(Row(id: id, candidate: c, status: .needsBrowser, title: user))
        case .pinterestShort(let url):
            rows.append(Row(id: id, candidate: c, status: .checking, title: url.host ?? "pin.it"))
            enqueue(id)
        case .unrecognised(let s):
            rows.append(Row(id: id, candidate: c, status: .rejected("Not a board"), title: s))
        }
    }

    /// Recognise `text` and, once every link has been looked up, import them all.
    func importNow(_ text: String) {
        ingest(text)
        Task {
            var waited = 0
            while stillChecking, waited < 200 { try? await Task.sleep(for: .milliseconds(150)); waited += 1 }
            start()
        }
    }

    func remove(_ id: String) {
        guard phase == .composing else { return }
        rows.removeAll { $0.id == id }
        queue.removeAll { $0 == id }
    }

    func setSelected(_ boardID: String, _ on: Bool) {
        for i in rows.indices { for j in rows[i].children.indices where rows[i].children[j].id == boardID { rows[i].children[j].selected = on } }
    }

    func selectAll(in rowID: String, _ on: Bool, owned: Bool? = nil) {
        guard let i = rows.firstIndex(where: { $0.id == rowID }) else { return }
        for j in rows[i].children.indices where owned == nil || (rows[i].children[j].owner == nil) == owned { rows[i].children[j].selected = on }
    }

    /// The boards that will be imported: every ready board and every ticked channel, each once.
    var selectedBoards: [BoardCandidate] {
        var seen = Set<String>(), out: [BoardCandidate] = []
        for r in rows {
            if r.status == .ready, let b = r.board, seen.insert(b.id).inserted { out.append(b) }
            for c in r.children where c.selected && seen.insert(c.id).inserted { out.append(c) }
        }
        return out
    }

    var selectedItemCount: Int { selectedBoards.reduce(0) { $0 + $1.reachableCount } }
    var stillChecking: Bool { rows.contains { $0.status == .checking || $0.status == .expanding } }

    // MARK: Looking things up (two at a time)

    private func enqueue(_ id: String) { queue.append(id); pump() }

    private func pump() {
        while checking < 2, !queue.isEmpty {
            let id = queue.removeFirst()
            checking += 1
            Task { await self.resolve(id); self.checking -= 1; self.pump() }
        }
    }

    private func resolve(_ id: String) async {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        switch row.candidate {
        case .board(let ref):
            do { update(id) { $0.board = nil }; let b = try await BoardPreflight.check(ref, loader: loader); update(id) { $0.board = b; $0.title = b.name; $0.status = .ready } }
            catch { update(id) { $0.status = Self.status(for: error) } }
        case .arenaUser(let slug):
            do {
                let list = try await ArenaDirectory(loader: loader).channels(user: slug)
                update(id) { $0.children = list; $0.status = list.isEmpty ? .rejected("No channels") : .ready }
            } catch { update(id) { $0.status = Self.status(for: error) } }
        case .pinterestShort(let url):
            do {
                let (_, response) = try await loader(LinkFetcher.request(url, accept: "text/html"))
                let found = response.url.flatMap { LinkHarvester.harvest($0.absoluteString).first }
                if let found, !found.isShort { replace(id, with: found) } else { replace(id, with: .unrecognised(url.absoluteString)) }
            } catch { update(id) { $0.status = Self.status(for: error) } }
        default: break
        }
    }

    /// A resolved short link becomes the row it points to.
    private func replace(_ id: String, with c: LinkCandidate) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let newID = key(c)
        if rows.contains(where: { $0.id == newID }) { rows.remove(at: i); return }
        rows.remove(at: i)
        add(c)
        if let j = rows.firstIndex(where: { $0.id == newID }), j != i, i < rows.count { rows.insert(rows.remove(at: j), at: i) }
    }

    private func update(_ id: String, _ change: (inout Row) -> Void) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        change(&rows[i])
    }

    static func status(for error: Error) -> Status {
        if let e = error as? BoardImportError {
            switch e {
            case .blocked(let why): return .blocked(why)
            case .notFoundOrPrivate: return .rejected("Private or missing")
            case .network: return .offline
            case .empty: return .rejected("Nothing to import")
            default: return .rejected("Not a board")
            }
        }
        if (error as? URLError)?.code == .notConnectedToInternet { return .offline }
        return .rejected("Not a board")
    }

    func retry(_ id: String) {
        update(id) { $0.status = $0.candidate.isUser ? .expanding : .checking }
        enqueue(id)
    }

    // MARK: Running

    func start() {
        guard phase == .composing, let app, let store = app.store, let service = serviceFor(app, store) else { return }
        let boards = selectedBoards
        guard !boards.isEmpty else { return }
        let direct = boards.filter { $0.via != .browser }
        let browser = boards.filter { $0.via == .browser }
        // boards that need the extension can't start without it: ask for it first, and carry on by itself once it is connected
        if !browser.isEmpty, !app.extensionPaired { app.extensionSetup.open(continueImport: true); return }
        let job = ImportJob(libraryId: app.libraryID, boards: direct)
        pendingBrowser = browser
        run(job, store: store, service: service, keepOpen: !browser.isEmpty)
        if !browser.isEmpty { collect(browser) }
    }

    // MARK: The browser extension

    var extensionPaired: Bool { app?.extensionPaired ?? false }
    @ObservationIgnored private var listNonce: String?
    @ObservationIgnored private(set) var collectNonce: String?
    private(set) var collecting: [String: Int] = [:]          // board id → pins scrolled so far
    /// Boards that only the browser extension can bring in full, until it hands each one over: shown as rows from the first second,
    /// so the screen is never empty while Chrome is still scrolling.
    private(set) var pendingBrowser: [BoardCandidate] = []
    /// Chrome hasn't touched the first board in a while: the extension may be missing, asleep or blocked.
    private(set) var browserStalled = false
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    /// The last board the extension sent that could not be read (dev demos print it).
    private(set) var lastReceiveError: String?

    /// A profile's boards, found by the extension scrolling the profile page.
    func openProfileInBrowser(_ rowID: String) {
        guard let app, let server = app.apiServer, let row = rows.first(where: { $0.id == rowID }), case .pinterestUser(let user) = row.candidate else { return }
        let nonce = server.jobs.create(.list(profile: user))
        listNonce = nonce
        update(rowID) { $0.status = .expanding }
        app.openInBrowser("https://www.pinterest.com/\(user)/#grails=\(nonce)")
    }

    func listed(nonce: String, boards: [ListedBoard]) {
        guard nonce == listNonce, let id = rows.first(where: { if case .pinterestUser = $0.candidate { $0.status == .expanding } else { false } })?.id,
              case .pinterestUser(let user)? = rows.first(where: { $0.id == id })?.candidate else { return }
        let children: [BoardCandidate] = boards.compactMap { b in
            guard case .board(let ref)? = LinkHarvester.harvest(b.url).first, case .pinterest = ref else { return nil }
            return BoardCandidate(ref: ref, name: b.name, count: b.count, covers: b.cover.flatMap(URL.init(string:)).map { [$0] } ?? [], parent: id, selected: true, via: .browser)
        }
        update(id) { $0.children = children; $0.status = children.isEmpty ? .rejected("No boards") : .ready; $0.title = user }
    }

    /// A Pinterest board read in full (the browser scrolls it) instead of just its latest 50.
    func useBrowser(_ boardID: String) {
        for i in rows.indices {
            if rows[i].board?.id == boardID { rows[i].board?.via = .browser }
            for j in rows[i].children.indices where rows[i].children[j].id == boardID { rows[i].children[j].via = .browser }
        }
    }

    private func collect(_ boards: [BoardCandidate]) {
        guard let app, let server = app.apiServer else { return }
        let urls = boards.map { $0.ref.webURL.absoluteString }
        let nonce = server.jobs.create(.collect(boards: urls))
        collectNonce = nonce
        for b in boards { collecting[b.id] = 0 }
        browserStalled = false
        app.openInBrowser(urls[0] + "#grails=\(nonce)")
        stallWatch?.cancel()
        stallWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled else { return }
            if self.collecting.values.allSatisfy({ $0 == 0 }), !self.pendingBrowser.isEmpty { self.browserStalled = true }
        }
    }

    func collectProgress(nonce: String, board: String, scrolled: Int) {
        guard nonce == collectNonce else { return }
        if let ref = LinkHarvester.harvest(board).first, case .board(let r) = ref { collecting[BoardCandidate.id(for: r)] = scrolled; browserStalled = false }
    }

    func collectDone(nonce: String) {
        guard nonce == collectNonce else { return }
        collectNonce = nil
        pendingBrowser = []
        stallWatch?.cancel()
        Task { await runner?.closeInput() }
    }

    /// Boards the extension scrolled: looked up, then added to the running job (or a job of their own).
    func receive(_ request: BoardImportRequest) async {
        guard let app, let store = app.store, let service = serviceFor(app, store) else { return }
        var tasks: [BoardTask] = []
        for b in request.allBoards where !b.pins.isEmpty {
            guard case .board(let ref)? = LinkHarvester.harvest(b.url).first, case .pinterest(let user, _) = ref else { continue }
            pendingBrowser.removeAll { $0.id == BoardCandidate.id(for: ref) }
            let images = Dictionary(b.pins.compactMap { p in p.image.map { (p.id, $0) } }, uniquingKeysWith: { a, _ in a })
            do {
                let remote = try await BoardImporter(loader: loader).fetchPinterestPins(ids: b.pins.map(\.id), ref: ref, name: b.name ?? ref.webURL.lastPathComponent, author: user, images: images)
                var t = BoardTask(candidate: BoardCandidate(ref: ref, name: remote.name, count: remote.entries.count, via: .browser))
                t.entries = remote.entries; t.skipped = remote.skipped; t.total = remote.entries.count
                tasks.append(t)
            } catch { collecting[BoardCandidate.id(for: ref)] = nil; lastReceiveError = "\(b.url): \(error)" }
        }
        guard !tasks.isEmpty else { return }
        if let runner, phase == .running { for t in tasks { await runner.append(t) } }
        else {
            // nobody asked (the extension's own button): a job of its own
            var job = ImportJob(libraryId: app.libraryID, boards: [])
            job.boards = tasks
            run(job, store: store, service: service)
        }
    }

    private func serviceFor(_ app: AppModel, _ store: LibraryStore) -> LibraryCaptureService? {
        guard fixtureNetwork else { return app.captureService }
        return LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
    }

    /// Carries on a job that was interrupted.
    func resume(_ job: ImportJob) {
        guard phase != .running, let app, let store = app.store, let service = serviceFor(app, store) else { return }
        var job = job
        for i in job.boards.indices { if job.boards[i].state == .stopped { job.boards[i].state = .queued } }
        run(job, store: store, service: service)
    }

    private func run(_ job: ImportJob, store: LibraryStore, service: LibraryCaptureService, keepOpen: Bool = false) {
        phase = .running
        order = job.boards.map(\.id)
        tasks = Dictionary(job.boards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        arrivals = []; arrivedCount = 0; finishedJob = nil
        let support = AppModel.supportURL
        let runner = ImportRunner(job: job, store: store, service: service, politeness: .standard, loader: loader, journal: ImportJournal.fileURL(for: job, in: support), keepOpen: keepOpen)
        self.runner = runner
        consumer = Task { [weak self] in
            for await event in runner.events() {
                guard let self else { return }
                switch event {
                case .updated(let t):
                    if self.tasks[t.id] == nil { self.order.append(t.id) }
                    self.tasks[t.id] = t
                case .itemAdded(_, let item):
                    self.arrivedCount += 1
                    self.arrivals.append(item)
                    if self.arrivals.count > 400 { self.arrivals.removeFirst(100) }
                    if self.arrivedCount % 6 == 0 { self.app?.reloadSoon() }
                case .finished(let done):
                    self.finishedJob = done
                    self.phase = .finished
                    ImportJournal.remove(done, in: support)
                    await self.app?.importFinished(done, openFirst: self.opensFirstCollection)
                }
            }
        }
    }

    /// Chrome never answered: open the first board in the browser again.
    func retryBrowser() {
        guard let app, let server = app.apiServer, let first = pendingBrowser.first else { return }
        let nonce = server.jobs.create(.collect(boards: pendingBrowser.map { $0.ref.webURL.absoluteString }))
        collectNonce = nonce
        browserStalled = false
        app.openInBrowser(first.ref.webURL.absoluteString + "#grails=\(nonce)")
        stallWatch?.cancel()
        stallWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled else { return }
            if self.collecting.values.allSatisfy({ $0 == 0 }), !self.pendingBrowser.isEmpty { self.browserStalled = true }
        }
    }

    func stopAll() { pendingBrowser = []; stallWatch?.cancel(); Task { await runner?.stopEverything() } }
    func stop(_ boardID: String) { Task { await runner?.stop(board: boardID) } }

    /// Takes back what this job added: the pictures go to the Trash, and the collections it made go if they are empty.
    func undoAll() {
        guard let job = finishedJob, let app else { return }
        let ids = job.boards.flatMap(\.addedIDs)
        Task { await app.undoImport(ids: ids, collections: job.boards.compactMap(\.collectionId)) }
    }

    func reset() {
        rows = []; phase = .composing; tasks = [:]; order = []; arrivals = []; arrivedCount = 0; finishedJob = nil
        queue = []; pendingBrowser = []; browserStalled = false; stallWatch?.cancel()
    }
}

extension LinkCandidate {
    var isUser: Bool { if case .arenaUser = self { true } else { false } }
    var isShort: Bool { if case .pinterestShort = self { true } else { false } }
}
