import AppKit
import GrailsKit

/// Import boards from Are.na, Pinterest and X: links go to the import panel, which runs them as one job.
extension AppModel {
    static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Grails", isDirectory: true)
    }

    /// An import that was cut off (the app quit) carries on where it was, quietly: its footer shows in the sidebar.
    func resumeInterruptedImport() {
        guard ProcessInfo.processInfo.environment["GRAILS_IMPORT_DEMO"] == nil, !importModel.isRunning,
              let job = ImportJournal.unfinished(libraryId: libraryID, in: Self.supportURL).first else { return }
        importModel.resume(job)
    }

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

    /// The browser extension scrolled some boards, or an X post link arrived through the API.
    func startPinterestImport(_ request: BoardImportRequest) {
        if request.source == "x" { if let link = request.url { startBoardImport(link) }; return }
        Task { await importModel.receive(request) }
    }

    // MARK: Pairing and the extension

    func allowPairing(_ request: PairingBroker.Request) {
        apiServer?.pairing.approve(request.id)
        pairRequest = nil
        extensionPaired = true
        UserDefaults.standard.set(true, forKey: "extensionPaired")
        if extensionSetup.isOpen { extensionSetup.connected = true }
        // an import was waiting for this: the sheet gets out of the way and the import starts
        if extensionSetup.continueImport {
            extensionSetup.continueImport = false
            extensionSetup.close()
            importModel.start()
        }
    }

    /// Forgets the pairing: a new code that no extension knows. Extensions ask to connect again.
    func disconnectExtensions() {
        _ = tokens.regenerate()
        extensionPaired = false
        UserDefaults.standard.set(false, forKey: "extensionPaired")
    }

    func denyPairing(_ request: PairingBroker.Request) {
        apiServer?.pairing.deny(request.id)
        pairRequest = nil
    }

    /// Opens a page in the default browser (the one the extension lives in).
    func openInBrowser(_ link: String) {
        browserOpener(link)
    }

    /// Puts the extension where it will stay (it survives app updates) and returns that folder.
    func copyExtensionFolder() -> URL? {
        guard let source = Bundle.main.url(forResource: "chrome", withExtension: nil) else { errorMessage = "The extension isn't in this build."; return nil }
        let support = Self.supportURL
        let dest = support.appendingPathComponent("Extension", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: source, to: dest) } catch { errorMessage = "Couldn't copy the extension: \(error.localizedDescription)"; return nil }
        return dest
    }
}
