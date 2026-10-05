import AppKit
import GrailsKit

/// Import boards from Are.na, Pinterest and X: links go to the import panel, which runs them as one job.
extension AppModel {
    func promptImportBoard() {
        if importModel.phase == .finished { importModel.reset() }
        importPanelOpen = true
    }

    /// A link that arrived from elsewhere (a pasted post): brought in without asking, once it is recognised.
    func startBoardImport(_ link: String) {
        guard !importModel.isRunning else { showToast("An import is already running"); return }
        importModel.importNow(link)
    }

    func cancelBoardImport() { importModel.stopAll() }

    func importFinished(_ job: ImportJob, openFirst: Bool) async {
        await reload()
        kickAutoTag()
        let added = job.boards.reduce(0) { $0 + $1.added + $1.alreadyHad }
        let skipped = job.boards.reduce(0) { $0 + $1.skippedCount + $1.failed }
        if openFirst, let first = job.boards.first(where: { $0.collectionId != nil && $0.added + $0.alreadyHad > 0 })?.collectionId { source = .collection(first) }
        showToast("Imported \(added.formatted())" + (skipped > 0 ? " · \(skipped.formatted()) skipped" : ""), seconds: 5)
    }

    /// Takes back what an import added: the pictures go to the Trash, and the collections it made go if nothing else is in them.
    func undoImport(ids: [String], collections cids: [String]) async {
        guard let store else { return }
        try? await store.softDelete(ids: ids)
        for cid in cids {
            var q = ItemQuery(); q.collectionId = cid
            if (try? await store.index.count(q)) == 0 { try? await store.deleteCollection(id: cid) }
        }
        await reload()
        showToast("Import undone")
    }

    /// The browser extension scrolled a whole board and sent its pin ids; Grails looks them up and imports.
    func startPinterestImport(_ request: BoardImportRequest) {
        guard boardImportTask == nil else { showToast("An import is already running"); return }
        if request.source == "x" { if let link = request.url { startBoardImport(link) }; return }
        boardImportTask = Task { [weak self] in
            await self?.importBoard(request: request)
            self?.boardImportTask = nil
        }
    }

    private func importBoard(request: BoardImportRequest) async {
        let importer = BoardImporter()
        let ref = request.url.flatMap(BoardRef.parse) ?? .pinterest(user: "pinterest", board: request.name)
        await importBoard { [weak self] in
            self?.boardImport = ("Looking up \(request.pinIds.count) pins on Pinterest…", 0, 0)
            return try await importer.fetchPinterestPins(ids: request.pinIds, ref: ref, name: request.name, author: nil)
        }
    }

    private func importBoard(_ readBoard: () async throws -> RemoteBoard) async {
        guard let store else { return }
        let service = captureService ?? LibraryCaptureService(store: { [weak self] in await self?.store })
        let importer = BoardImporter()
        defer { boardImport = nil }
        do {
            let board = try await readBoard()
            let label = "Importing “\(board.name)”"
            boardImport = (label, 0, board.entries.count)
            let (summary, undo) = try await recorded("Import “\(board.name)”", in: store) {
                try await importer.run(board, into: store, service: service) { [weak self] done, total in
                    Task { @MainActor in self?.boardImport = (label, done, total) }
                }
            }
            if !undo.isEmpty { pushUndo(undo) }
            await reload()
            if let id = summary.collectionId, !summary.cancelled, summary.added + summary.alreadyHad > 0 { source = .collection(id) }
            var text = summary.cancelled ? "Import stopped. " + summary.headline : summary.headline
            if let note = board.note { text += "\n" + note }
            showToast(text, seconds: board.note == nil ? 4.5 : 8)
        } catch is CancellationError {
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
