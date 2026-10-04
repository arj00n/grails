import Foundation

public struct SaveRequest: Codable, Sendable {
    /// Direct URL of an image or video file.
    public var mediaUrl: String?
    /// The page the media (or the link itself) came from.
    public var pageUrl: String?
    public var title: String?
    /// Raw file bytes, when the extension already has them (blob:/data: images, canvas, screenshots).
    public var dataBase64: String?
    /// A screenshot of the page (JPEG/PNG), used as the link's snapshot.
    public var snapshotBase64: String?
    public var collectionId: String?
    public var tags: [String]?
    public var author: String?

    public init(mediaUrl: String? = nil, pageUrl: String? = nil, title: String? = nil, dataBase64: String? = nil,
                snapshotBase64: String? = nil, collectionId: String? = nil, tags: [String]? = nil, author: String? = nil) {
        self.mediaUrl = mediaUrl; self.pageUrl = pageUrl; self.title = title; self.dataBase64 = dataBase64
        self.snapshotBase64 = snapshotBase64; self.collectionId = collectionId; self.tags = tags; self.author = author
    }
}

public struct SaveResult: Codable, Sendable, Equatable {
    public var ok = true
    public var id: String
    public var kind: String
    public var duplicate: Bool
    public var name: String
}

public struct CollectionInfo: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var kind: String
    public var parentId: String?
}

public enum CaptureError: Error, Equatable, LocalizedError {
    case nothingToSave
    case badURL(String)
    case downloadFailed(String)
    case unsupported(String)
    case noLibrary

    public var errorDescription: String? {
        switch self {
        case .nothingToSave: "Nothing to save: send a mediaUrl, dataBase64, or pageUrl."
        case .badURL(let s): "Not a valid URL: \(s)"
        case .downloadFailed(let s): "Couldn't download the file: \(s)"
        case .unsupported(let s): "Unsupported content: \(s)"
        case .noLibrary: "No library is open in Stash."
        }
    }
}

/// A whole board handed over by the browser extension (it scrolled the page and collected the pin ids).
public struct BoardImportRequest: Codable, Sendable, Equatable {
    public var source: String            // "pinterest", or "x" (a post link; Stash reads its media itself)
    public var name: String
    public var url: String?
    public var pinIds: [String]
    public init(source: String = "pinterest", name: String = "", url: String? = nil, pinIds: [String] = []) {
        self.source = source; self.name = name; self.url = url; self.pinIds = pinIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url)
        pinIds = try c.decodeIfPresent([String].self, forKey: .pinIds) ?? []
    }

    /// Something the app can act on: pins to look up, or a post link to read.
    public var isActionable: Bool { source == "x" ? url.flatMap(BoardRef.parse)?.isPost == true : !pinIds.isEmpty }
}

public struct BoardImportAccepted: Codable, Sendable, Equatable {
    public var ok = true
    public var count: Int
    public init(count: Int) { self.count = count }
}

/// What the local API (and the paste / menu bar paths) call to save things.
public protocol CaptureService: Sendable {
    func save(_ request: SaveRequest) async throws -> SaveResult
    func collections() async -> [CollectionInfo]
    /// Starts importing a board in the background; returns once it is accepted.
    func importBoard(_ request: BoardImportRequest) async throws -> BoardImportAccepted
    var libraryName: String { get async }
}

extension CaptureService {
    public func importBoard(_ request: BoardImportRequest) async throws -> BoardImportAccepted { throw CaptureError.unsupported("board import") }
}
