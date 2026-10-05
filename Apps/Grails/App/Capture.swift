import AppKit
import GrailsKit
import UniformTypeIdentifiers

/// What was on the pasteboard (or dropped), in the order we prefer to save it.
struct PasteboardCapture {
    var files: [URL] = []
    var urls: [URL] = []
    var imageData: Data?
    var isEmpty: Bool { files.isEmpty && urls.isEmpty && imageData == nil }

    /// Files win; then web URLs (better than the bitmap a browser also puts there: the original, full-size file);
    /// then raw image data (screenshots, images copied from other apps).
    @MainActor
    static func read(_ pb: NSPasteboard) -> PasteboardCapture {
        var out = PasteboardCapture()
        out.files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !out.files.isEmpty { return out }
        var urls: [URL] = []
        if let web = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] { urls += web.filter { !$0.isFileURL } }
        if let text = pb.string(forType: .string) {
            for line in text.split(whereSeparator: \.isNewline) {
                let c = CaptureClassifier.classify(String(line))
                if let u = c.url, c.kind != .text { urls.append(u) }
            }
        }
        var seen = Set<String>()
        out.urls = urls.filter { seen.insert($0.absoluteString).inserted && ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if out.urls.isEmpty {
            if let png = pb.data(forType: .png) { out.imageData = png }
            else if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) { out.imageData = rep.representation(using: .png, properties: [:]) }
        }
        return out
    }
}

extension AppModel {
    // MARK: Startup

    func startCapture() async {
        guard captureService == nil else { return }
        let env = ProcessInfo.processInfo.environment
        let service = LibraryCaptureService(store: { [weak self] in await self?.store })
        service.onSaved = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                // a board import saves many items through here; it reloads once at the end and shows its own progress
                guard self.boardImport == nil, !self.importModel.isRunning else { return }
                await self.reload()
                if !result.duplicate { self.showToast(result.kind == "link" ? "Saved link" : "Saved to Grails") }
                if result.kind == "link", !result.duplicate { await self.autoSnapshotIfNeeded(id: result.id) }
            }
        }
        service.onBoardImport = { [weak self] request in Task { @MainActor in self?.startPinterestImport(request) } }
        captureService = service

        if env["GRAILS_NO_API"] == nil {
            let server = LocalAPIServer(service: service, tokens: tokens)
            do {
                let port = try await server.start(port: env["GRAILS_API_PORT"].flatMap(UInt16.init) ?? LocalAPIServer.defaultPort)
                apiServer = server
                apiPort = port
                apiStatus = "Listening on 127.0.0.1:\(port)"
            } catch {
                apiStatus = "Not running: \(error.localizedDescription)"
            }
        } else {
            apiStatus = "Disabled"
        }
        applyDockPolicy()
        if menuBar == nil, env["GRAILS_NO_MENUBAR"] == nil { menuBar = MenuBarController(model: self) }
    }

    func applyDockPolicy() {
        let hide = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }

    // MARK: Paste / drop

    var captureContext: (collectionId: String?, tags: [String]) {
        if case .collection(let id) = source { return (id, []) }
        if case .tag(let t) = source { return (nil, [t]) }
        return (nil, [])
    }

    /// ⌘V in the grid. `forceLink` (⌥⌘V) saves URLs as link cards even when they point at an image or video file.
    func paste(forceLink: Bool = false, toInbox: Bool = false, from pb: NSPasteboard = .general) {
        let capture = PasteboardCapture.read(pb)
        guard !capture.isEmpty else { showToast("Nothing to paste"); return }
        Task { await save(capture, forceLink: forceLink, toInbox: toInbox) }
    }

    func save(_ capture: PasteboardCapture, forceLink: Bool = false, toInbox: Bool = false) async {
        guard let store, let service = captureService else { return }
        let ctx = toInbox ? (collectionId: String?.none, tags: [String]()) : captureContext
        let count = capture.files.count + capture.urls.count + (capture.imageData == nil ? 0 : 1)
        do {
            let (_, undo) = try await recorded("Paste", in: store) {
                if !capture.files.isEmpty {
                    await importFiles(capture.files, collectionId: ctx.collectionId, tag: ctx.tags.first, recordUndo: false)
                }
                for url in capture.urls {
                    // a post on X: bring in its pictures and videos rather than a link card
                    if !forceLink, BoardRef.parse(url.absoluteString)?.isPost == true { startBoardImport(url.absoluteString); continue }
                    let kind = CaptureClassifier.classify(url.absoluteString).kind
                    let asLink = forceLink || kind == .page
                    let req = asLink
                        ? SaveRequest(pageUrl: url.absoluteString, collectionId: ctx.collectionId, tags: ctx.tags)
                        : SaveRequest(mediaUrl: url.absoluteString, collectionId: ctx.collectionId, tags: ctx.tags)
                    do { _ = try await service.save(req) } catch { showToast("Couldn't save \(url.host ?? "link"): \(error.localizedDescription)") }
                }
                if let png = capture.imageData {
                    let name = "Pasted image \(Self.timestamp())"
                    _ = try? await service.save(SaveRequest(title: name, dataBase64: png.base64EncodedString(), collectionId: ctx.collectionId, tags: ctx.tags))
                }
            }
            pushUndo(undo)
            await reload()
            if count > 0, capture.files.isEmpty { showToast("Pasted \(count) \(count == 1 ? "item" : "items")") }
        } catch { errorMessage = "Paste failed: \(error.localizedDescription)" }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    // MARK: Links

    func openLinkInBrowser(_ id: String) {
        guard let store else { return }
        Task {
            guard let item = try? await store.item(id: id), item.kind == .link, let s = item.source?.pageUrl, let url = URL(string: s) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    func setLinkDisplay(_ mode: String, ids: [String]) {
        Task { await perform("Show Link As") { store in for id in ids { try await store.setLinkDisplay(mode, for: id) } } }
    }

    func retakeSnapshot(id: String) {
        guard let store else { return }
        Task {
            guard let item = try? await store.item(id: id), let s = item.source?.pageUrl, let url = URL(string: s) else { return }
            showToast("Taking snapshot…")
            guard let png = await LinkSnapshotter.capture(url: url) else { showToast("Couldn't take a snapshot"); return }
            await perform("Retake Snapshot") { try await $0.setSnapshot(png, for: id) }
            ThumbnailLoader.shared.clear()
            showToast("Snapshot updated")
        }
    }

    /// Links with no preview image get a page snapshot in the background (turn off in Settings).
    func autoSnapshotIfNeeded(id: String) async {
        guard UserDefaults.standard.object(forKey: "autoSnapshotLinks") == nil || UserDefaults.standard.bool(forKey: "autoSnapshotLinks"),
              let store, let item = try? await store.item(id: id), item.extras["linkDisplay"] == "title",
              let s = item.source?.pageUrl, let url = URL(string: s), ["http", "https"].contains(url.scheme ?? "") else { return }
        guard let png = await LinkSnapshotter.capture(url: url) else { return }
        try? await store.setSnapshot(png, for: id)
        await reload()
    }
}
