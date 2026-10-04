import AppKit
import StashKit

/// Import a public Are.na channel or Pinterest board from its link.
extension AppModel {
    func promptImportBoard() {
        guard boardImportTask == nil else { showToast("An import is already running"); return }
        // a board link already on the clipboard is almost certainly what they want
        let clip = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let looksRight = BoardRef.parse(clip) != nil || BoardRef.isPinterestShortLink(clip)
        prompt = PromptRequest(
            title: "Import from Are.na or Pinterest",
            placeholder: "Board link", initial: looksRight ? clip : "", confirmTitle: "Import"
        ) { [weak self] link in
            guard let self, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            self.startBoardImport(link)
        }
    }

    func startBoardImport(_ link: String) {
        guard boardImportTask == nil else { return }
        boardImportTask = Task { [weak self] in
            await self?.importBoard(link)
            self?.boardImportTask = nil
        }
    }

    func cancelBoardImport() { boardImportTask?.cancel() }

    /// The browser extension scrolled a whole board and sent its pin ids; Stash looks them up and imports.
    func startPinterestImport(_ request: BoardImportRequest) {
        guard boardImportTask == nil else { showToast("An import is already running"); return }
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

    private func importBoard(_ link: String) async {
        let importer = BoardImporter()
        await importBoard { [weak self] in
            self?.boardImport = ("Looking up the link…", 0, 0)
            let ref = try await importer.resolve(link)
            self?.boardImport = ("Reading the \(ref.service) \(ref.kindName)…", 0, 0)
            return try await importer.fetch(ref) { [weak self] found, total in
                Task { @MainActor in self?.boardImport = ("Reading the \(ref.service) \(ref.kindName)… \(found)\(total.map { " of \($0)" } ?? "")", 0, 0) }
            }
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
