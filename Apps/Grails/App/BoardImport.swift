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

    /// Items arriving from an import: the library shows them in steps (at most one reload every 2 s, none behind onboarding), so the grid
    /// never reflows on every picture.
    func reloadWhileImporting() {
        guard onboarding == nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastImportReload) >= 2 else { return }
        lastImportReload = now
        reloadSoon()
    }

    func importFinished(_ job: ImportJob, openFirst: Bool) async {
        importLandingReady = false
        defer { importLandingReady = true }
        await reload()
        kickAutoTag()
        // on the canvas, one calm fit once everything has arrived (the camera stayed put while items streamed in)
        if viewMode == .canvas { await syncCanvas(); canvasRequest = CanvasRequest(kind: .fit) }
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
        // the guide ticks its last step, then leaves, and Grails comes back to the front
        if guide.isShowing {
            guide.finishAll()
            guidePanel.refit()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                guidePanel.hide()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        // a secret board that was waiting for this can now be read in the browser
        importModel.useExtensionForSecretBoards()
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
        // the browser the extension went into, when there is one; otherwise the default
        if let b = ExtensionSetup.preferredBrowser, let url = URL(string: link), ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_DEMO"] == nil {
            NSWorkspace.shared.open([url], withApplicationAt: b, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        browserOpener(link)
    }

    /// If the extension was installed unpacked from the app's copy, keeps that copy current: a new build brings a new extension, and the person
    /// only has to press reload on the browser's extensions page.
    func refreshExtensionCopy() {
        let dest = Self.supportURL.appendingPathComponent("Extension", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dest.path), let source = Bundle.main.url(forResource: "chrome", withExtension: nil) else { return }
        func version(_ dir: URL) -> String? {
            (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as? [String: Any])?["version"] as? String
        }
        guard version(source) != version(dest) else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: source, to: dest)
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
