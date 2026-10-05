import Foundation

/// Where one board is in an import.
public enum BoardState: Codable, Equatable, Sendable {
    case queued
    case reading(found: Int, total: Int?)
    case downloading(done: Int, total: Int)
    case waiting(until: Date)
    case done
    case failed(String)
    case blocked(String)
    case stopped
}

/// One board's share of a job: what it is, how far it got, what it added (so it can be undone on its own).
public struct BoardTask: Codable, Sendable, Identifiable, Equatable {
    public var candidate: BoardCandidate
    public var state: BoardState = .queued
    public var collectionId: String?
    public var total = 0
    /// Entries handled so far, by position in `entries`; a resumed job skips them.
    public var handled: Set<Int> = []
    public var added = 0, alreadyHad = 0, failed = 0
    public var skipped: [String: Int] = [:]
    public var addedIDs: [String] = []
    public var note: String?
    /// What was read from the board, kept so resuming doesn't read it (or need the browser) again.
    public var entries: [RemoteBoard.Entry]?

    public var id: String { candidate.id }
    public init(candidate: BoardCandidate) { self.candidate = candidate }
    public var skippedCount: Int { skipped.values.reduce(0, +) }
    /// How many entries this board will have handled when it is done: what was read, else what it is expected to hold.
    public var expected: Int { total > 0 ? total : candidate.reachableCount }
}

public struct ImportJob: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var libraryId: String
    public var boards: [BoardTask]
    public var tags: [String] = []

    public init(libraryId: String, boards: [BoardCandidate], tags: [String] = []) {
        self.libraryId = libraryId
        self.boards = boards.map(BoardTask.init(candidate:))
        self.tags = tags
    }

    public var isFinished: Bool {
        boards.allSatisfy { t in switch t.state { case .done, .failed, .blocked, .stopped: true; default: false } }
    }
    /// Boards that still have something to do, including ones stopped part-way (they can be resumed).
    public var needsWork: Bool {
        boards.contains { t in switch t.state { case .done, .failed, .blocked: false; default: true } }
    }
    public var totalPlanned: Int { boards.reduce(0) { $0 + max($1.total, $1.candidate.count ?? 0) } }
    public var totalHandled: Int { boards.reduce(0) { $0 + $1.handled.count } }
}

public enum ImportEvent: Sendable {
    case updated(BoardTask)
    /// A new item arrived (for the collage).
    case itemAdded(board: String, item: String)
    case finished(ImportJob)
}

public enum RowAction: Equatable, Sendable { case retry, resume, remove, stop, full }

/// What a row says about a board: a label and a second line, as words (never more than four in a label except for errors).
public enum RowPresenter {
    public static func row(_ t: BoardTask) -> (label: String, detail: String?, action: RowAction?) {
        func n(_ v: Int) -> String { v.formatted() }
        switch t.state {
        case .queued: return ("Queued", nil, .remove)
        case .reading(let found, let total):
            return (total.map { "Reading \(n(found))/\(n($0))" } ?? "Reading \(n(found))", nil, .stop)
        case .downloading(let done, let total): return ("\(n(done))/\(n(total))", nil, .stop)
        case .waiting(let until):
            let s = max(0, Int(until.timeIntervalSinceNow.rounded(.up)))
            return ("Waiting \(s / 60):\(String(format: "%02d", s % 60))", nil, nil)
        case .done:
            let detail = t.skippedCount > 0 ? t.skipped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") : nil
            return ("\(n(t.added + t.alreadyHad)) ✓", detail ?? (t.failed > 0 ? "\(t.failed) failed" : nil), nil)
        case .failed(let why): return ("Failed", why, .retry)
        case .blocked(let why): return ("Blocked", why, .retry)
        case .stopped: return ("Stopped \(n(t.handled.count))/\(n(max(t.total, t.handled.count)))", nil, .resume)
        }
    }
}
