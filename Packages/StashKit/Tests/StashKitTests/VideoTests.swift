import AVFoundation
import Foundation
import Testing
@testable import StashKit

@Suite struct VideoTests {
    /// A real (tiny) H.264 file: `frames` solid frames at 10 fps.
    static func makeMP4(width: Int = 160, height: Int = 90, frames: Int = 20) async throws -> URL {
        let url = TestSupport.tempDir().appendingPathComponent("clip.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pb = buffer else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let bytes = CVPixelBufferGetBytesPerRow(pb) * height
                memset(base, Int32(40 + i * 8), bytes)                                 // grey that brightens frame by frame
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func readsSizeDurationAndPosterFromARealVideo() async throws {
        let url = try await Self.makeMP4(width: 160, height: 90, frames: 20)
        let info = try #require(Thumbnailer.videoInfo(at: url))
        #expect(info.width == 160 && info.height == 90)
        #expect(abs(info.durationSec - 2.0) < 0.3)
        let poster = try #require(info.poster)
        #expect(poster.count > 100 && poster.prefix(2) == Data([0xFF, 0xD8]))      // a JPEG
        #expect(Thumbnailer.videoInfo(at: TestSupport.makePNG(in: TestSupport.tempDir(), name: "x")) == nil)   // not a video
    }

    @Test func aVideoBecomesAnItemWithAThumbnailAndDuration() async throws {
        let (store, _) = try TestSupport.newStore()
        let url = try await Self.makeMP4(width: 120, height: 200, frames: 30)
        let item = try await store.addItem(fileAt: url).item
        #expect(item.kind == .video && item.width == 120 && item.height == 200)
        #expect(abs((item.durationSec ?? 0) - 3.0) < 0.3)
        #expect(FileManager.default.fileExists(atPath: store.layout.thumbURL(item.id).path))
        let stored = try #require(try await store.item(id: item.id))
        #expect(stored.durationSec == item.durationSec)
        var q = ItemQuery(); q.kinds = [.video]
        #expect(try await store.index.count(q) == 1)
    }
}
