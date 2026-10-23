import Foundation
import XCTest
import GrailsSync

final class HandoffTests: XCTestCase {
    func testTransferPinsTheNewKeyAndTheNewOwnerCanRemoveTheOldOne() throws {
        let owner = DeviceKey()
        let next = DeviceKey()
        let member = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "n@studio.com", role: .admin),
            TeamMember(email: "m@studio.com", role: .member),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        XCTAssertNil(OwnershipTransfer.propose(body: start, adminEmail: "m@studio.com", devicePublicKey: member.publicKey))
        XCTAssertNil(OwnershipTransfer.propose(body: start, adminEmail: "n@studio.com", devicePublicKey: ""))
        XCTAssertNil(OwnershipTransfer.propose(body: start, adminEmail: "missing@studio.com", devicePublicKey: next.publicKey))
        let proposed = try XCTUnwrap(OwnershipTransfer.propose(body: start, adminEmail: "n@studio.com", devicePublicKey: next.publicKey))
        XCTAssertEqual(proposed.generation, 1)
        XCTAssertEqual(proposed.role(of: "o@studio.com"), .admin)
        var moved = proposed
        moved.generation = 2
        let signed = try TeamDocument.sign(moved, key: owner)
        XCTAssertEqual(signed.signerPublicKey, owner.publicKey)
        let accepted = TeamDirectory.accept(signed: signed, trusted: trusted, devices: ["n@studio.com": next.publicKey])
        XCTAssertEqual(accepted?.pinnedOwnerKey, next.publicKey)
        XCTAssertEqual(accepted?.body.ownerEmail, "n@studio.com")
        var removed = try XCTUnwrap(accepted).body
        removed.generation = 3
        removed.members.removeAll { $0.email == "o@studio.com" }
        let after = TeamDirectory.accept(signed: try TeamDocument.sign(removed, key: next), trusted: accepted, devices: ["n@studio.com": next.publicKey])
        XCTAssertEqual(after?.body.members.map(\.email), ["m@studio.com", "n@studio.com"])
        XCTAssertEqual(after?.body.role(of: "n@studio.com"), .owner)
        XCTAssertTrue(OwnershipTransfer.needsToken(role: .owner, cloudflareSaved: false))
        XCTAssertFalse(OwnershipTransfer.needsToken(role: .owner, cloudflareSaved: true))
        XCTAssertFalse(OwnershipTransfer.needsToken(role: .admin, cloudflareSaved: false))
        XCTAssertEqual(MemberCutover.emails(in: proposed), ["m@studio.com", "o@studio.com"])
    }

    func testRecoveryRoundTripHidesTheKey() throws {
        let key = DeviceKey()
        let sealed = try RecoveryFile.seal(privateKey: key.privateRaw, password: "company-pass", iterations: InviteCrypto.acceptedIterations.lowerBound)
        XCTAssertNil(sealed.range(of: key.privateRaw))
        XCTAssertFalse(String(describing: key).contains(Digests.hex(key.privateRaw)))
        let opened = try RecoveryFile.open(sealed, password: "company-pass")
        XCTAssertEqual(opened, key.privateRaw)
        XCTAssertThrowsError(try RecoveryFile.open(sealed, password: "wrong")) { error in
            XCTAssertEqual(error as? RecoveryError, .wrongPassword)
        }
        XCTAssertThrowsError(try RecoveryFile.open(Data("nope".utf8), password: "company-pass")) { error in
            XCTAssertEqual(error as? RecoveryError, .malformed)
        }
    }

    func testARecoveryFileWithAnOutOfRangeCountIsMalformed() throws {
        let sealed = try RecoveryFile.seal(privateKey: DeviceKey().privateRaw, password: "company-pass", iterations: InviteCrypto.acceptedIterations.lowerBound)
        for count: UInt32 in [0, 2, 99_999, 2_000_001, 0xFFFF_FFFF] {
            var forged = sealed
            withUnsafeBytes(of: count.bigEndian) { forged.replaceSubrange(2..<6, with: $0) }
            XCTAssertThrowsError(try RecoveryFile.open(forged, password: "company-pass"), "\(count)") { error in
                XCTAssertEqual(error as? RecoveryError, .malformed)
            }
        }
    }

    func testCopyChecksBytesAndLeavesTheSource() async throws {
        let source = MemoryObjectStore()
        let destination = MemoryObjectStore()
        let body = Data("thumb-bytes".utf8)
        let marker = Data("old-marker".utf8)
        await source.seed("items/a/thumb.jpg", body: body)
        await source.seed(MoveNotice.key, body: marker)
        try await LibraryMover.copy(from: source, to: destination)
        let copied = await destination.body("items/a/thumb.jpg")
        XCTAssertEqual(copied, body)
        let leaked = await destination.body(MoveNotice.key)
        XCTAssertNil(leaked)
        let still = await source.body("items/a/thumb.jpg")
        XCTAssertEqual(still, body)
        let markerKept = await source.body(MoveNotice.key)
        XCTAssertEqual(markerKept, marker)
        let sourceDeletes = await source.counts()
        XCTAssertEqual(sourceDeletes.deletes, 0)
    }

    func testCopyPicksUpEditsThatLandDuringTheMove() async throws {
        let inner = MemoryObjectStore()
        let destination = MemoryObjectStore()
        await inner.seed("items/a/thumb.jpg", body: Data("v1".utf8))
        let source = ChangingSource(inner)
        try await LibraryMover.copy(from: source, to: destination)
        let copiedA = await destination.body("items/a/thumb.jpg")
        let copiedB = await destination.body("items/b/thumb.jpg")
        let sourceA = await inner.body("items/a/thumb.jpg")
        let marker = await destination.body(MoveNotice.key)
        XCTAssertEqual(copiedA, Data("version-two".utf8))
        XCTAssertEqual(copiedB, Data("new-during-move".utf8))
        XCTAssertEqual(sourceA, Data("version-two".utf8))
        XCTAssertNil(marker)
    }

    func testCopyRejectsAFlippedReadBack() async throws {
        let source = MemoryObjectStore()
        let inner = MemoryObjectStore()
        let destination = FlippingGet(inner)
        await source.seed("items/a/thumb.jpg", body: Data("thumb-bytes".utf8))
        do {
            try await LibraryMover.copy(from: source, to: destination)
            XCTFail("expected a checksum failure")
        } catch let error as MoveError {
            XCTAssertEqual(error, .checksum("items/a/thumb.jpg"))
        }
        let still = await source.keys()
        XCTAssertEqual(still, ["items/a/thumb.jpg"])
        let sourceDeletes = await source.counts()
        XCTAssertEqual(sourceDeletes.deletes, 0)
    }

    func testFreezeMarkerHasNoSecretAndBlocksTheOldBucket() async throws {
        let secret = "SECRET-VALUE-do-not-leak-9f3a"
        let notice = MoveNotice(endpoint: "https://new.example", bucket: "old-library", region: "auto", at: Date(timeIntervalSince1970: 1_700_000_000))
        let store = MemoryObjectStore()
        try await LibraryMover.freeze(store, notice: notice)
        let stored = await store.body(MoveNotice.key)
        let raw = try XCTUnwrap(stored)
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("apiToken"))
        let read = try await MoveNotice.read(from: store)
        XCTAssertEqual(read, notice)
        XCTAssertEqual(MoveNotice.prompt, "This library has moved. Ask the owner to invite you again.")
        XCTAssertFalse(LibraryScanner.shouldSync(MoveNotice.key))

        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        await store.seed("items/a/thumb.jpg", body: Data("thumb".utf8))
        let frozen = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5", bucketName: "old-library")
        let report = try await frozen.syncOnce()
        XCTAssertEqual(report.moved, notice)
        let counts = await store.counts()
        XCTAssertEqual(counts.lists, 0)
        XCTAssertEqual(counts.puts, 1)

        let unnamed = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let also = try await unnamed.syncOnce()
        XCTAssertEqual(also.moved?.bucket, "old-library")
        let afterUnnamed = await store.counts()
        XCTAssertEqual(afterUnnamed.lists, 0)
    }

    func testANoticeForAnotherBucketDoesNotFreeze() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let notice = MoveNotice(endpoint: "https://new.example", bucket: "old-library", region: "auto", at: Date(timeIntervalSince1970: 1_700_000_000))
        try await LibraryMover.freeze(store, notice: notice)
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5", bucketName: "new-library")
        let report = try await engine.syncOnce()
        XCTAssertNil(report.moved)
        let counts = await store.counts()
        XCTAssertGreaterThan(counts.lists, 0)
    }

    func testOnlyTheOwnerDeletesAFrozenBucket() async throws {
        let store = MemoryObjectStore()
        await store.seed("items/a/thumb.jpg", body: Data("thumb".utf8))
        do {
            try await LibraryMover.deleteSource(store: store, role: .owner)
            XCTFail("expected not frozen")
        } catch let error as MoveError {
            XCTAssertEqual(error, .notFrozen)
        }
        let notice = MoveNotice(endpoint: "https://new.example", bucket: "old-library", region: "auto", at: Date(timeIntervalSince1970: 1_700_000_000))
        try await LibraryMover.freeze(store, notice: notice)
        do {
            try await LibraryMover.deleteSource(store: store, role: .member)
            XCTFail("expected not allowed")
        } catch let error as MoveError {
            XCTAssertEqual(error, .notAllowed)
        }
        let kept = await store.keys()
        XCTAssertEqual(kept, ["items/a/thumb.jpg", MoveNotice.key])
        try await LibraryMover.deleteSource(store: store, role: .owner)
        let left = await store.keys()
        XCTAssertTrue(left.isEmpty)
    }
}

private actor FlippingGet: ObjectStore {
    private let inner: MemoryObjectStore

    init(_ inner: MemoryObjectStore) { self.inner = inner }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        let got = try await inner.get(key)
        guard let first = got.body.first else { return got }
        return ObjectGet(body: Data([first ^ 0xFF]) + got.body.dropFirst(), etag: got.etag)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

/// The first read of `items/a` returns the original bytes, then the source gains a new version and a new key.
private actor ChangingSource: ObjectStore {
    private let inner: MemoryObjectStore
    private var bumped = false

    init(_ inner: MemoryObjectStore) { self.inner = inner }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        if key == "items/a/thumb.jpg", !bumped {
            bumped = true
            let got = try await inner.get(key)
            await inner.seed("items/a/thumb.jpg", body: Data("version-two".utf8))
            await inner.seed("items/b/thumb.jpg", body: Data("new-during-move".utf8))
            return got
        }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}
