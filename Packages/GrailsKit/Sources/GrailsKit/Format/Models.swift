import Foundation

public struct ItemKind: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public static let image: ItemKind = "image"
    public static let gif: ItemKind = "gif"
    public static let video: ItemKind = "video"
    public static let svg: ItemKind = "svg"
    public static let pdf: ItemKind = "pdf"
    public static let raw: ItemKind = "raw"
    public static let vector: ItemKind = "vector"
    public static let lottie: ItemKind = "lottie"
    public static let link: ItemKind = "link"
    public static let color: ItemKind = "color"
    public static let file: ItemKind = "file"
    /// Not an item: a titled section divider in the grid (a canvas cluster). Never stored.
    public static let section: ItemKind = "section"
}

public struct ItemSource: Codable, Hashable, Sendable {
    public var url: String?
    public var pageUrl: String?
    public var site: String?
    public var author: String?
    public var title: String?

    public init(url: String? = nil, pageUrl: String? = nil, site: String? = nil, author: String? = nil, title: String? = nil) {
        self.url = url; self.pageUrl = pageUrl; self.site = site; self.author = author; self.title = title
    }
}

public struct PaletteColor: Codable, Hashable, Sendable {
    public var hex: String
    public var weight: Double
    public init(hex: String, weight: Double) { self.hex = hex; self.weight = weight }
}

/// `items/<ULID>/item.json`. Fields this version doesn't know are kept in `extras` and written back untouched.
public struct Item: Codable, Hashable, Sendable, Identifiable {
    public var schema: Int
    public var id: String
    public var kind: ItemKind
    public var file: String?
    public var name: String
    public var ext: String?
    public var bytes: Int64?
    public var width: Int?
    public var height: Int?
    public var durationSec: Double?
    public var sha256: String?
    public var source: ItemSource?
    public var tags: [String]
    /// collectionId → fractional-index order key
    public var collections: [String: String]
    public var liked: Bool
    public var note: String
    public var palette: [PaletteColor]
    public var ocrText: String
    public var camera: JSONValue?
    public var addedAt: Date
    public var addedBy: String
    public var updatedAt: Date
    public var updatedBy: String
    public var deletedAt: Date?
    public var extras: [String: JSONValue]

    public init(
        id: String = ULID().string, kind: ItemKind, file: String? = nil, name: String, ext: String? = nil,
        bytes: Int64? = nil, width: Int? = nil, height: Int? = nil, durationSec: Double? = nil,
        sha256: String? = nil, source: ItemSource? = nil, tags: [String] = [],
        collections: [String: String] = [:], liked: Bool = false, note: String = "",
        palette: [PaletteColor] = [], ocrText: String = "", camera: JSONValue? = nil,
        addedAt: Date = .grailsNow, addedBy: String, updatedAt: Date? = nil, updatedBy: String? = nil,
        deletedAt: Date? = nil, extras: [String: JSONValue] = [:]
    ) {
        self.schema = GrailsKit.schemaVersion
        self.id = id; self.kind = kind; self.file = file; self.name = name; self.ext = ext
        self.bytes = bytes; self.width = width; self.height = height; self.durationSec = durationSec
        self.sha256 = sha256; self.source = source; self.tags = tags; self.collections = collections
        self.liked = liked; self.note = note; self.palette = palette; self.ocrText = ocrText
        self.camera = camera; self.addedAt = addedAt; self.addedBy = addedBy
        self.updatedAt = updatedAt ?? addedAt; self.updatedBy = updatedBy ?? addedBy
        self.deletedAt = deletedAt; self.extras = extras
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, id, kind, file, name, ext, bytes, width, height, durationSec, sha256, source, tags
        case collections, liked, note, palette, ocrText, camera, addedAt, addedBy, updatedAt, updatedBy, deletedAt
    }
    private static let known = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .file
        file = try c.decodeIfPresent(String.self, forKey: .file)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        ext = try c.decodeIfPresent(String.self, forKey: .ext)
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        durationSec = try c.decodeIfPresent(Double.self, forKey: .durationSec)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
        source = try c.decodeIfPresent(ItemSource.self, forKey: .source)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        collections = try c.decodeIfPresent([String: String].self, forKey: .collections) ?? [:]
        liked = try c.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        palette = try c.decodeIfPresent([PaletteColor].self, forKey: .palette) ?? []
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        camera = try c.decodeIfPresent(JSONValue.self, forKey: .camera)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        addedBy = try c.decodeIfPresent(String.self, forKey: .addedBy) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? addedAt
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? addedBy
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extras = try Extras.decode(from: decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(ext, forKey: .ext)
        try c.encodeIfPresent(bytes, forKey: .bytes)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(durationSec, forKey: .durationSec)
        try c.encodeIfPresent(sha256, forKey: .sha256)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(tags, forKey: .tags)
        try c.encode(collections, forKey: .collections)
        try c.encode(liked, forKey: .liked)
        try c.encode(note, forKey: .note)
        try c.encode(palette, forKey: .palette)
        try c.encode(ocrText, forKey: .ocrText)
        try c.encodeIfPresent(camera, forKey: .camera)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(addedBy, forKey: .addedBy)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try Extras.encode(extras, known: Self.known, to: encoder)
    }
}

/// `collections/<ULID>.json`
public struct GrailsCollection: Codable, Hashable, Sendable, Identifiable {
    public var schema: Int
    public var id: String
    /// "folder" (contains other collections) or "collection" (contains items)
    public var kind: String
    public var name: String
    public var parentId: String?
    public var order: String
    public var archived: Bool
    public var coverItemId: String?
    public var updatedAt: Date
    public var updatedBy: String
    public var extras: [String: JSONValue]

    public init(
        id: String = ULID().string, kind: String = "collection", name: String, parentId: String? = nil,
        order: String = FractionalIndex.initial, archived: Bool = false, coverItemId: String? = nil,
        updatedAt: Date = .grailsNow, updatedBy: String, extras: [String: JSONValue] = [:]
    ) {
        self.schema = GrailsKit.schemaVersion
        self.id = id; self.kind = kind; self.name = name; self.parentId = parentId; self.order = order
        self.archived = archived; self.coverItemId = coverItemId; self.updatedAt = updatedAt
        self.updatedBy = updatedBy; self.extras = extras
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, id, kind, name, parentId, order, archived, coverItemId, updatedAt, updatedBy
    }
    private static let known = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "collection"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        order = try c.decodeIfPresent(String.self, forKey: .order) ?? FractionalIndex.initial
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        coverItemId = try c.decodeIfPresent(String.self, forKey: .coverItemId)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
        extras = try Extras.decode(from: decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(order, forKey: .order)
        try c.encode(archived, forKey: .archived)
        try c.encodeIfPresent(coverItemId, forKey: .coverItemId)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
        try Extras.encode(extras, known: Self.known, to: encoder)
    }
}

/// `library.json`
public struct LibraryManifest: Codable, Hashable, Sendable {
    public var schema: Int
    public var id: String
    public var name: String
    public var createdAt: Date
    public var extras: [String: JSONValue]

    public init(id: String = ULID().string, name: String, createdAt: Date = .grailsNow, extras: [String: JSONValue] = [:]) {
        self.schema = GrailsKit.schemaVersion
        self.id = id; self.name = name; self.createdAt = createdAt; self.extras = extras
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schema, id, name, createdAt }
    private static let known = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        extras = try Extras.decode(from: decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try Extras.encode(extras, known: Self.known, to: encoder)
    }
}
