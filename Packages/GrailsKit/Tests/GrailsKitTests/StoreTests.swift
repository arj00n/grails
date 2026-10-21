import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GrailsKit

@Suite struct StoreTests {
    @Test func addItemCopiesFileWritesThumbAndJSONAndIndexes() async throws {
        let (store, root) = try TestSupport.newStore(handle: "ana")
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "red", width: 1200, height: 800)
        let result = try await store.addItem(fileAt: png, tags: ["Food", "food", " hero "])
        guard case .added(let item) = result else { Issue.record("expected .added"); return }

        #expect(item.kind == .image)
        #expect(item.width == 1200 && item.height == 800)
        #expect(item.addedBy == "ana")
        #expect(item.tags == ["Food", "hero"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("items/\(item.id)/original.png").path))
        let thumb = try Data(contentsOf: root.appendingPathComponent("items/\(item.id)/thumb.jpg"))
        let info = Thumbnailer.imageInfo(at: root.appendingPathComponent("items/\(item.id)/thumb.jpg"))
        #expect(thumb.count > 100)
        #expect(info?.width == 512 && info?.height == 341)
        #expect(try await store.index.count(ItemQuery()) == 1)
    }

    @Test func addingSameFileTwiceReturnsExistingItem() async throws {
        let (store, _) = try TestSupport.newStore()
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "a")
        let first = try await store.addItem(fileAt: png)
        let second = try await store.addItem(fileAt: png)
        guard case .duplicate(let dup) = second else { Issue.record("expected .duplicate"); return }
        #expect(dup.id == first.item.id)
        #expect(try await store.index.count(ItemQuery()) == 1)
        let forced = try await store.addItem(fileAt: png, dedupe: false)
        #expect(forced.item.id != first.item.id)
    }

    @Test func transparentImagesGetOpaqueJPEGThumbnails() async throws {
        let (store, _) = try TestSupport.newStore()
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "clear", alpha: 0)
        let item = try await store.addItem(fileAt: png).item
        let data = try Data(contentsOf: await store.thumbURL(for: item.id))
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    @Test func updateStampsAuthorAndRefreshesSearch() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "plain")
        let item = try await store.addItem(fileAt: png).item
        await store.setUserHandle("ben")
        let updated = try await store.updateItem(id: item.id) { $0.tags = ["biryani"]; $0.note = "brass handi, top-down"; $0.liked = true }
        #expect(updated.updatedBy == "ben" && updated.addedBy == "ana")
        #expect(try await store.index.query(ItemQuery(text: "biry")).map(\.id) == [item.id])
        #expect(try await store.index.query(ItemQuery(text: "handi")).map(\.id) == [item.id])
        var liked = ItemQuery(); liked.likedOnly = true
        #expect(try await store.index.count(liked) == 1)
        _ = try await store.updateItem(id: item.id) { $0.tags = [] }
        #expect(try await store.index.query(ItemQuery(text: "biryani")).isEmpty)
    }

    @Test func trashRestoreAndEmpty() async throws {
        let (store, root) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        let a = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "a", rgb: (1, 0, 0))).item
        let b = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "b", rgb: (0, 1, 0))).item
        try await store.softDelete(ids: [a.id, b.id])
        #expect(try await store.index.count(ItemQuery()) == 0)
        var trash = ItemQuery(); trash.deleted = true
        #expect(try await store.index.count(trash) == 2)

        try await store.restore(ids: [a.id])
        #expect(try await store.index.count(ItemQuery()) == 1)

        #expect(try await store.emptyTrash() == 1)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("items/\(b.id)").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".trash/\(b.id)/item.json").path))
        #expect(try await store.purgeTrash(olderThanDays: 30) == 0)
        #expect(try await store.purgeTrash(olderThanDays: 30, now: Date().addingTimeInterval(31 * 86400)) == 1)
    }

    @Test func collectionsKeepOrderKeys() async throws {
        let (store, _) = try TestSupport.newStore()
        let c = try await store.createCollection(name: "Packaging")
        let dir = TestSupport.tempDir()
        let a = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "a", rgb: (1, 0, 0)), collectionIds: [c.id]).item
        let b = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "b", rgb: (0, 1, 0)), collectionIds: [c.id]).item
        #expect(a.collections[c.id]! < b.collections[c.id]!)
        var q = ItemQuery(); q.collectionId = c.id
        #expect(try await store.index.count(q) == 2)
        #expect(try await store.index.collections().map(\.name) == ["Packaging"])
    }

    @Test func numericNameSortPutsTwoBeforeTen() async throws {
        let (store, _) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        for (i, n) in ["Shot 10", "Shot 2", "shot 1"].enumerated() {
            _ = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "f\(i)", rgb: (Double(i) / 3, 0.5, 0.5)), name: n)
        }
        var q = ItemQuery(); q.sort = .nameAsc
        #expect(try await store.index.query(q).map(\.name) == ["shot 1", "Shot 2", "Shot 10"])
    }

    @Test func cameraExifIsCapturedOnImport() async throws {
        let (store, _) = try TestSupport.newStore()
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "src")
        let jpg = png.deletingLastPathComponent().appendingPathComponent("shot.jpg")
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil)!
        let dest = CGImageDestinationCreateWithURL(jpg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R5"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 1.8, kCGImagePropertyExifISOSpeedRatings: [400]],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let item = try await store.addItem(fileAt: jpg).item
        guard case .object(let cam)? = item.camera else { Issue.record("no camera info"); return }
        #expect(cam["make"] == .string("Canon") && cam["model"] == .string("EOS R5"))
        #expect(cam["iso"] == .int(400) && cam["aperture"] == .double(1.8))
        #expect(try await store.item(id: item.id)?.camera == item.camera)
    }

    @Test func inboxIsItemsInNoCollection() async throws {
        let (store, _) = try TestSupport.newStore()
        let c = try await store.createCollection(name: "C")
        let dir = TestSupport.tempDir()
        _ = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "a", rgb: (1, 0, 0)), collectionIds: [c.id])
        let loose = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "b", rgb: (0, 1, 0))).item
        var q = ItemQuery(); q.unfiled = true
        #expect(try await store.index.query(q).map(\.id) == [loose.id])
    }
}
