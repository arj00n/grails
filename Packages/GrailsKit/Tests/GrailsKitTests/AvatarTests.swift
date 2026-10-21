import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GrailsKit

@Suite struct AvatarTests {
    @Test func squareCropStripsMetadataAndRejectsTheRest() throws {
        let wide = try sample(width: 100, height: 20, comment: "secret-token") { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 20))
            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 40, y: 0, width: 20, height: 20))
        }
        guard case .success(let jpeg) = AvatarImage.jpeg(from: wide) else {
            Issue.record("expected a jpeg")
            return
        }
        let image = try decoded(jpeg)
        #expect(image.width == 512)
        #expect(image.height == 512)
        let corner = pixel(image, x: 4, y: 4)
        #expect(corner.g > 180)
        #expect(corner.g > corner.r)
        #expect(corner.g > corner.b)
        let props = String(describing: properties(of: jpeg))
        #expect(!props.contains("secret-token"))

        #expect(AvatarImage.jpeg(from: Data(count: AvatarImage.maxInputBytes + 1)) == .failure(.tooLarge))
        #expect(AvatarImage.jpeg(from: Data("not a picture".utf8)) == .failure(.notAnImage))
    }

    @Test func aLargePhotoIsStoredSmall() throws {
        let source = try uncompressedImage(pixels: 2048)
        #expect(source.count >= 12_000_000)
        guard case .success(let jpeg) = AvatarImage.jpeg(from: source) else {
            Issue.record("expected a jpeg")
            return
        }
        #expect(jpeg.count <= AvatarImage.maxOutputBytes)
        let image = try decoded(jpeg)
        #expect(image.width <= AvatarImage.side)
        #expect(image.height <= AvatarImage.side)
        let root = TestSupport.tempDir("avatar-large")
        let layout = LibraryLayout(root: root)
        let saved = try AvatarStore.write(jpeg: jpeg, handle: "Ada", in: layout, authorized: true, stamps: [], now: Date(timeIntervalSince1970: 1_700_000_100))
        let url = try #require(AvatarStore.fileURL(handle: "Ada", in: layout))
        let stored = try Data(contentsOf: url)
        #expect(stored.count <= AvatarImage.maxOutputBytes)
        #expect(stored == jpeg)
        #expect(saved.digest == AvatarStore.digest(of: stored))
    }

    @Test func rateLimitAllowsFiveThenWaits() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var stamps: [Date] = []
        for index in 0..<5 {
            let now = start.addingTimeInterval(Double(index))
            #expect(AvatarRate.allows(stamps, now: now))
            stamps = AvatarRate.stamp(stamps, now: now)
        }
        #expect(stamps.count == 5)
        #expect(!AvatarRate.allows(stamps, now: start.addingTimeInterval(30)))
        #expect(AvatarRate.allows(stamps, now: start.addingTimeInterval(AvatarRate.window + 1)))
    }

    @Test func onlyAnAuthorizedChangeIsStoredAndARenameKeepsIt() throws {
        let root = TestSupport.tempDir("avatar")
        let layout = LibraryLayout(root: root)
        let jpeg = try jpegSquare()
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        #expect(throws: AvatarError.unauthorized) {
            try AvatarStore.write(jpeg: jpeg, handle: "Ada", in: layout, authorized: false, stamps: [], now: now)
        }
        #expect(AvatarStore.fileURL(handle: "Ada", in: layout).map { FileManager.default.fileExists(atPath: $0.path) } == false)

        let saved = try AvatarStore.write(jpeg: jpeg, handle: "Ada", in: layout, authorized: true, stamps: [], now: now)
        let url = try #require(AvatarStore.fileURL(handle: "Ada", in: layout))
        let stored = try Data(contentsOf: url)
        #expect(stored == jpeg)
        let profile = try GrailsJSON.decode(MemberRecord.self, from: Data(contentsOf: root.appendingPathComponent(".members/ada.json")))
        #expect(profile.avatar == saved.digest)
        #expect(profile.avatar == AvatarStore.digest(of: jpeg))

        var stamps = saved.stamps
        for index in 1..<5 {
            let step = now.addingTimeInterval(Double(index))
            stamps = try AvatarStore.write(jpeg: jpeg, handle: "Ada", in: layout, authorized: true, stamps: stamps, now: step).stamps
        }
        #expect(throws: AvatarError.rateLimited) {
            try AvatarStore.write(jpeg: jpeg, handle: "Ada", in: layout, authorized: true, stamps: stamps, now: now.addingTimeInterval(20))
        }

        try Members.record(handle: "Ada", in: layout, now: now.addingTimeInterval(10), minInterval: 0, name: "Ada")
        let kept = try GrailsJSON.decode(MemberRecord.self, from: Data(contentsOf: root.appendingPathComponent(".members/ada.json")))
        #expect(kept.avatar == saved.digest)

        try Members.adopt(name: "Ada Lane", previous: "Ada", in: layout, now: now.addingTimeInterval(30))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".members/ada.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".members/ada-lane.json").path))
        let renamed = try #require(Members.profiles(in: layout).first { $0.name == "Ada Lane" })
        #expect(!renamed.id.isEmpty)
        #expect(renamed.previousHandles.contains("ada"))
        #expect(renamed.avatar == saved.digest)
        let moved = try #require(AvatarStore.memberPhotoURL(id: renamed.id, in: layout))
        #expect(try Data(contentsOf: moved) == jpeg)
    }

    private func jpegSquare() throws -> Data {
        let data = try sample(width: 8, height: 8, comment: nil) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard case .success(let jpeg) = AvatarImage.jpeg(from: data) else { throw AvatarImage.Failure.notAnImage }
        return jpeg
    }

    private func sample(width: Int, height: Int, comment: String?, paint: (CGContext) -> Void) throws -> Data {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let image = ({ paint(ctx); return ctx.makeImage() })() else { throw AvatarImage.Failure.notAnImage }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AvatarImage.Failure.notAnImage
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let comment {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: comment]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw AvatarImage.Failure.notAnImage }
        return data as Data
    }

    private func uncompressedImage(pixels: Int) throws -> Data {
        guard let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw AvatarImage.Failure.notAnImage }
        var rng: UInt64 = 0x1234_5678
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let count = ctx.bytesPerRow * pixels
        for index in 0..<count {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1
            ptr[index] = UInt8(truncatingIfNeeded: rng >> 33)
        }
        guard let image = ctx.makeImage() else { throw AvatarImage.Failure.notAnImage }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else {
            throw AvatarImage.Failure.notAnImage
        }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyTIFFCompression: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw AvatarImage.Failure.notAnImage }
        return data as Data
    }

    private func decoded(_ data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw AvatarImage.Failure.notAnImage }
        return image
    }

    private func properties(of data: Data) -> [String: Any] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return [:] }
        return props
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }
}
