import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A profile photo: a square JPEG, at most 512 px and 200 KB, with no camera metadata.
public enum AvatarImage {
    public static let side = 512
    public static let maxOutputBytes = 200_000
    /// Refuses a file before decode. A photo around 12 MB is still accepted and stored small.
    public static let maxInputBytes = 32_000_000

    public enum Failure: Error, Equatable {
        case tooLarge
        case notAnImage
    }

    /// Center-crops, scales to at most `side`, and re-encodes under `maxOutputBytes`. The destination carries compression quality only, so EXIF and GPS do not survive.
    public static func jpeg(from data: Data) -> Result<Data, Failure> {
        if data.count > maxInputBytes { return .failure(.tooLarge) }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return .failure(.notAnImage) }
        guard let type = CGImageSourceGetType(src) as String?, UTType(type)?.conforms(to: .image) == true else {
            return .failure(.notAnImage)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let square = cropSquare(oriented),
              let jpeg = jpegWithinBudget(square) else {
            return .failure(.notAnImage)
        }
        return .success(jpeg)
    }

    /// Tries 512 px at falling quality, then a smaller edge, and returns the first file that fits.
    static func jpegWithinBudget(_ square: CGImage) -> Data? {
        var edge = side
        while edge >= 64 {
            guard let scaled = scale(square, to: edge) else { return nil }
            let flat = Thumbnailer.flattened(scaled)
            var quality = 0.82
            while quality >= 0.1 - 0.000_1 {
                if let jpeg = Thumbnailer.encodeJPEG(flat, quality: quality), jpeg.count <= maxOutputBytes {
                    return jpeg
                }
                quality -= 0.12
            }
            edge = edge * 3 / 4
        }
        return nil
    }

    static func cropSquare(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let side = min(width, height)
        guard side > 0 else { return nil }
        let origin = CGPoint(x: (width - side) / 2, y: (height - side) / 2)
        return image.cropping(to: CGRect(origin: origin, size: CGSize(width: side, height: side)))
    }

    static func scale(_ image: CGImage, to side: Int) -> CGImage? {
        guard side > 0, let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }
}

/// Five photo changes in ten minutes.
public enum AvatarRate {
    public static let maxChanges = 5
    public static let window: TimeInterval = 600

    public static func allows(_ stamps: [Date], now: Date) -> Bool {
        recent(stamps, now: now).count < maxChanges
    }

    public static func stamp(_ stamps: [Date], now: Date) -> [Date] {
        recent(stamps, now: now) + [now]
    }

    private static func recent(_ stamps: [Date], now: Date) -> [Date] {
        stamps.filter { now.timeIntervalSince($0) < window && now.timeIntervalSince($0) >= 0 }
    }
}

public struct AvatarSaved: Equatable, Sendable {
    public var digest: String
    public var stamps: [Date]
}

public enum AvatarError: Error, Equatable {
    case unauthorized
    case rateLimited
    case emptyHandle
}

/// Which avatar a member chose. Stored in `.members/<id>.look.json` beside their profile, so a 0.3.8 rewrite of the profile cannot drop it, and it still syncs with `.members`.
public struct AvatarLook: Codable, Equatable, Sendable {
    /// False shows the generated blob even when a photo file is still around (a removal that has not synced yet).
    public var usesPhoto: Bool
    /// An index into the generated avatar's palette. Nil picks one from the member id.
    public var tint: Int?
    /// Seeds the generated blob's expression (Shuffle). Nil uses the member id, so everyone has a face before choosing one.
    /// Stored as `character` because older versions seeded a character with it; any stored seed is simply a face now.
    public var character: Int?

    public init(usesPhoto: Bool = false, tint: Int? = nil, character: Int? = nil) {
        self.usesPhoto = usesPhoto
        self.tint = tint
        self.character = character
    }

    /// `glyph` is the single letter older versions stored; it is read so that choice still picks a face, never written.
    enum CodingKeys: String, CodingKey { case usesPhoto = "photo", tint, character, glyph }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usesPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .usesPhoto)) ?? false
        tint = (try? c.decodeIfPresent(Int.self, forKey: .tint)) ?? nil
        character = (try? c.decodeIfPresent(Int.self, forKey: .character)) ?? nil
        if character == nil, let glyph = (try? c.decodeIfPresent(String.self, forKey: .glyph)) ?? nil {
            character = Self.legacyCharacter(glyph)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(usesPhoto, forKey: .usesPhoto)
        try c.encodeIfPresent(tint, forKey: .tint)
        try c.encodeIfPresent(character, forKey: .character)
    }

    /// The expression seed an older single-letter choice maps to: FNV-1a of its first visible character, so the same choice gives
    /// the same face on every Mac. Blank gives nil (the member id's face).
    public static func legacyCharacter(_ glyph: String) -> Int? {
        guard let first = glyph.first(where: { !$0.isWhitespace && !$0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }) else { return nil }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in String(first).utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return Int(h & 0x7FFF_FFFF)
    }

    /// A new expression seed, different from `current`. Kept to 31 bits so it survives any JSON reader.
    public static func shuffled(from current: Int?, using rng: inout some RandomNumberGenerator) -> Int {
        var next: Int
        repeat { next = Int.random(in: 0...0x7FFF_FFFF, using: &rng) } while next == current
        return next
    }

    /// A new colour out of `count`, different from `current` whenever there is another to pick.
    public static func shuffledTint(from current: Int?, count: Int, using rng: inout some RandomNumberGenerator) -> Int {
        guard count > 1 else { return 0 }
        var next: Int
        repeat { next = Int.random(in: 0..<count, using: &rng) } while next == current
        return next
    }
}

/// The photo lives beside the member profile (`.members/<handle>.avatar.jpg`) so the bucket syncs it with that file.
public enum AvatarStore {
    public static func fileName(_ handle: String) -> String? {
        let name = Handle.normalize(handle)
        return name.isEmpty ? nil : name + ".avatar.jpg"
    }

    public static func fileURL(handle: String, in layout: LibraryLayout) -> URL? {
        guard let name = fileName(handle) else { return nil }
        return Members.folder(layout).appendingPathComponent(name)
    }

    /// The photo for a stable member id. The id is already a filename-safe token, so it is not run through handle normalization.
    public static func memberPhotoURL(id: String, in layout: LibraryLayout) -> URL? {
        guard Members.isSafeMemberId(id) else { return nil }
        return Members.folder(layout).appendingPathComponent(id + ".avatar.jpg")
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes a prepared JPEG. `authorized` is `TeamPermissions.canSetAvatar` for the actor. Returns the new rate stamps.
    @discardableResult
    public static func write(jpeg: Data, handle: String, in layout: LibraryLayout, authorized: Bool, stamps: [Date], now: Date = Date()) throws -> AvatarSaved {
        guard authorized else { throw AvatarError.unauthorized }
        guard AvatarRate.allows(stamps, now: now) else { throw AvatarError.rateLimited }
        let saved = try place(jpeg: jpeg, handle: handle, in: layout, now: now)
        return AvatarSaved(digest: saved, stamps: AvatarRate.stamp(stamps, now: now))
    }

    /// Puts the JPEG in place and records its digest on the member profile. Used for a save and for a rename.
    @discardableResult
    public static func place(jpeg: Data, handle: String, in layout: LibraryLayout, now: Date = Date()) throws -> String {
        guard Members.fileName(handle) != nil else { throw AvatarError.emptyHandle }
        let existing = Members.profile(matching: handle, in: layout)
        let url = (existing?.id).flatMap { memberPhotoURL(id: $0, in: layout) } ?? fileURL(handle: handle, in: layout)
        guard let url else { throw AvatarError.emptyHandle }
        let digest = digest(of: jpeg)
        try FileManager.default.createDirectory(at: Members.folder(layout), withIntermediateDirectories: true)
        try AtomicFile.write(jpeg, to: url)
        var record = existing ?? MemberRecord(handle: Handle.normalize(handle), firstSeen: now, lastSeen: now, avatar: digest)
        record.avatar = digest
        if record.look != nil { record.look?.usesPhoto = true }
        record.lastSeen = now
        try Members.save(record, in: layout)
        return digest
    }

    /// Takes the photo away: the file goes and the profile says to draw the generated blob, so a copy that has not synced away yet
    /// is ignored by teammates on this version.
    public static func clear(handle: String, in layout: LibraryLayout, now: Date = Date()) throws {
        guard var record = Members.profile(matching: handle, in: layout) else { return }
        for url in [memberPhotoURL(id: record.id, in: layout), fileURL(handle: record.handle, in: layout), fileURL(handle: handle, in: layout)].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        record.avatar = nil
        var look = record.look ?? AvatarLook()
        look.usesPhoto = false
        record.look = look
        record.lastSeen = now
        try Members.save(record, in: layout)
    }
}
