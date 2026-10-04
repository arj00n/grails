import CryptoKit
import Foundation

/// Saves captures into the current library: downloads or decodes media, or builds a link card.
public final class LibraryCaptureService: CaptureService, @unchecked Sendable {
    private let storeProvider: @Sendable () async -> LibraryStore?
    private let fetcher: LinkFetcher
    private let download: LinkFetcher.Loader
    /// Called after each successful save (the app reloads its grid).
    public var onSaved: (@Sendable (SaveResult) -> Void)?
    /// Called when the extension hands over a whole board (the app runs the import and shows its progress).
    public var onBoardImport: (@Sendable (BoardImportRequest) -> Void)?

    public init(
        fetcher: LinkFetcher = LinkFetcher(),
        download: @escaping LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) },
        store: @escaping @Sendable () async -> LibraryStore?
    ) {
        self.fetcher = fetcher; self.download = download; self.storeProvider = store
    }

    public var libraryName: String { get async { await storeProvider()?.manifest.name ?? "" } }

    public func collections() async -> [CollectionInfo] {
        guard let store = await storeProvider() else { return [] }
        let all = (try? await store.index.collections()) ?? []
        return all.filter { !$0.archived }.map { CollectionInfo(id: $0.id, name: $0.name, kind: $0.kind, parentId: $0.parentId) }
    }

    public func importBoard(_ request: BoardImportRequest) async throws -> BoardImportAccepted {
        guard await storeProvider() != nil else { throw CaptureError.noLibrary }
        guard ["pinterest", "x"].contains(request.source), request.isActionable, let handler = onBoardImport else { throw CaptureError.unsupported("nothing to import") }
        handler(request)
        return BoardImportAccepted(count: max(request.pinIds.count, 1))
    }

    public func save(_ r: SaveRequest) async throws -> SaveResult {
        guard let store = await storeProvider() else { throw CaptureError.noLibrary }
        let tags = r.tags ?? []
        let collectionIds = r.collectionId.map { [$0] } ?? []
        let pageURL = r.pageUrl.flatMap(URL.init(string:))
        let result: AddResult

        if let b64 = r.dataBase64, let data = Data(base64Encoded: b64), !data.isEmpty {
            let ext = MediaSniffer.fileExtension(forData: data) ?? r.mediaUrl.flatMap(URL.init(string:))?.pathExtension.lowercased()
            guard let ext, !ext.isEmpty else { throw CaptureError.unsupported("unrecognised file type") }
            let temp = try writeTemp(data, ext: ext)
            defer { try? FileManager.default.removeItem(at: temp.deletingLastPathComponent()) }
            let source = ItemSource(url: r.mediaUrl, pageUrl: r.pageUrl, site: (pageURL ?? r.mediaUrl.flatMap(URL.init(string:))).flatMap(CaptureClassifier.siteName(for:)), author: r.author, title: r.title)
            result = try await store.addItem(fileAt: temp, name: r.title ?? friendlyName(r.mediaUrl), source: source, tags: tags, collectionIds: collectionIds)
        } else if let media = r.mediaUrl {
            guard let url = URL(string: media), url.scheme != nil else { throw CaptureError.badURL(media) }
            let (temp, suggested) = try await downloadFile(url, referer: pageURL)
            defer { try? FileManager.default.removeItem(at: temp.deletingLastPathComponent()) }
            let source = ItemSource(url: media, pageUrl: r.pageUrl, site: CaptureClassifier.siteName(for: pageURL ?? url), author: r.author, title: r.title)
            result = try await store.addItem(fileAt: temp, name: r.title ?? suggested, source: source, tags: tags, collectionIds: collectionIds)
        } else if let page = r.pageUrl {
            guard let url = pageURL, url.scheme != nil else { throw CaptureError.badURL(page) }
            let snapshot = r.snapshotBase64.flatMap { Data(base64Encoded: $0) }
            result = try await addLink(url, titleHint: r.title, snapshot: snapshot, tags: tags, collectionIds: collectionIds, store: store)
        } else {
            throw CaptureError.nothingToSave
        }

        let saved = SaveResult(id: result.item.id, kind: result.item.kind.rawValue, duplicate: { if case .duplicate = result { true } else { false } }(), name: result.item.name)
        onSaved?(saved)
        return saved
    }

    /// Creates (or finds) a link card for `url`: fetches title and preview image, keeps an optional page snapshot.
    public func addLink(_ url: URL, titleHint: String? = nil, snapshot: Data? = nil, tags: [String] = [], collectionIds: [String] = [], store: LibraryStore) async throws -> AddResult {
        let fetched = await fetcher.fetch(url)
        let isFigma = CaptureClassifier.isFigma(url)
        return try await store.addLink(
            url: url, title: titleHint ?? fetched.metadata.title, site: fetched.metadata.siteName ?? CaptureClassifier.siteName(for: url),
            author: fetched.metadata.author, summary: fetched.metadata.description, previewImage: fetched.imageData, snapshot: snapshot,
            badge: isFigma ? "figma" : nil, tags: tags, collectionIds: collectionIds
        )
    }

    // MARK: Downloading

    private func writeTemp(_ data: Data, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stash-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("capture.\(ext)")
        try data.write(to: url)
        return url
    }

    private func downloadFile(_ url: URL, referer: URL?) async throws -> (URL, String) {
        var req = LinkFetcher.request(url, accept: "image/*,video/*,*/*;q=0.8")
        if let referer { req.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let data: Data, response: URLResponse
        do { (data, response) = try await download(req) } catch { throw CaptureError.downloadFailed(error.localizedDescription) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw CaptureError.downloadFailed("HTTP \(http.statusCode)") }
        guard !data.isEmpty else { throw CaptureError.downloadFailed("empty response") }
        var ext = url.pathExtension.lowercased()
        if let sniffed = MediaSniffer.fileExtension(forData: data) { ext = sniffed }
        else if ext.isEmpty || ext.count > 5 { ext = MediaSniffer.fileExtension(forMIME: response.mimeType) ?? "" }
        guard !ext.isEmpty else { throw CaptureError.unsupported("unrecognised file type") }
        return (try writeTemp(data, ext: ext), friendlyName(url.absoluteString))
    }

    private func friendlyName(_ urlString: String?) -> String {
        guard let s = urlString, let u = URL(string: s) else { return "Saved item" }
        let base = u.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? u.lastPathComponent
        return base.isEmpty || base == "/" ? (CaptureClassifier.siteName(for: u) ?? "Saved item") : base
    }
}

public enum MediaSniffer {
    /// Recognises common media by magic bytes (more trustworthy than a URL's extension).
    public static func fileExtension(forData d: Data) -> String? {
        let b = [UInt8](d.prefix(32))
        guard b.count >= 4 else { return nil }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if b.starts(with: Array("GIF8".utf8)) { return "gif" }
        if b.count >= 12, Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WEBP".utf8) { return "webp" }
        if b.count >= 12, Array(b[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if brand.hasPrefix("avif") || brand.hasPrefix("avis") { return "avif" }
            if brand.hasPrefix("heic") || brand.hasPrefix("heix") || brand.hasPrefix("mif1") { return "heic" }
            if brand.hasPrefix("qt") { return "mov" }
            return "mp4"
        }
        if b.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return "webm" }
        if b.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if let s = String(data: d.prefix(512), encoding: .utf8), s.contains("<svg") { return "svg" }
        return nil
    }

    public static func fileExtension(forMIME mime: String?) -> String? {
        switch mime?.lowercased() {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/gif": "gif"
        case "image/webp": "webp"
        case "image/avif": "avif"
        case "image/svg+xml": "svg"
        case "image/heic": "heic"
        case "video/mp4": "mp4"
        case "video/quicktime": "mov"
        case "video/webm": "webm"
        case "application/pdf": "pdf"
        default: nil
        }
    }
}
