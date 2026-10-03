import Foundation

extension LibraryStore {
    public func canvasBoard(key: String) -> CanvasBoard? { readBoard(key: key) }

    func readBoard(key: String) -> CanvasBoard? {
        guard let data = try? Data(contentsOf: layout.canvasURL(key)) else { return nil }
        return try? StashJSON.decode(CanvasBoard.self, from: data)
    }

    func noteBefore(canvas key: String, ids: [String], board: CanvasBoard?) {
        guard recorder != nil else { return }
        for id in ids {
            if recorder?.canvases[key]?.keys.contains(id) == true { continue }
            recorder?.canvases[key, default: [:]][id] = .some(board?.placements[id])
        }
    }

    /// Writes placements into a board, merging with whatever is on disk right now (a teammate may have moved other items
    /// since this Mac last read it). `removing` drops placements. Returns the board as written.
    @discardableResult
    public func updatePlacements(boardKey key: String, _ updates: [String: CanvasPlacement], removing: Set<String> = []) async throws -> CanvasBoard {
        var board = readBoard(key: key) ?? CanvasBoard(key: key)
        noteBefore(canvas: key, ids: Array(updates.keys) + Array(removing), board: board)
        let now = Date().timeIntervalSince1970
        for (id, var p) in updates { p.at = now; board.placements[id] = p }
        for id in removing { board.placements[id] = nil }
        board.updatedAt = .stashNow
        board.updatedBy = userHandle
        try writeBoard(board)
        return board
    }

    func writeBoard(_ board: CanvasBoard) throws {
        try FileManager.default.createDirectory(at: layout.canvasDir, withIntermediateDirectories: true)
        try AtomicFile.write(StashJSON.encodeCompact(board), to: layout.canvasURL(board.key))
    }

    /// Items that no longer exist in the library (or are trashed for good) don't need a place on any board.
    public func pruneBoard(key: String, keeping ids: Set<String>) async throws {
        guard var board = readBoard(key: key) else { return }
        let stale = board.placements.keys.filter { !ids.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale { board.placements[id] = nil }
        board.updatedAt = .stashNow
        try writeBoard(board)
    }
}
