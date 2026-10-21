import Foundation
import XCTest
import GrailsSync

final class RenameTests: XCTestCase {
    func testBlankNamesAreRejectedAndWhitespaceIsTrimmed() {
        XCTAssertNil(LibraryName.normalized("   "))
        XCTAssertNil(LibraryName.normalized("\n"))
        XCTAssertEqual(LibraryName.normalized("  Night Shift  "), "Night Shift")
    }

    func testRenameKeepsTheTeamBlock() throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let original = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let renamed = try LibraryName.apply(original, name: "Night Shift")
        let object = try JSONSerialization.jsonObject(with: renamed) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "Night Shift")
        XCTAssertEqual(canonical(renamed), canonical(original))
        XCTAssertNotNil(canonical(original))
    }

    func testPublishUsesIfMatchAndTheOtherMacDownloadsIt() async throws {
        let store = MemoryObjectStore()
        let ownerRoot = try TestLibrary.makeRoot()
        let memberRoot = try TestLibrary.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: ownerRoot)
            try? FileManager.default.removeItem(at: memberRoot)
        }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: ownerRoot)
        let owner = BucketSyncEngine(store: store, root: ownerRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))

        let before = try await store.get("library.json")
        let stored = await owner.currentManifest()
        XCTAssertEqual(stored.entries["library.json"]?.etag, before.etag)
        try before.body.write(to: memberRoot.appendingPathComponent("library.json"))
        let member = BucketSyncEngine(store: store, root: memberRoot, merger: ClosureMerger { _, local, _ in local }, manifest: stored, appVersion: "0.3.5")
        let renamed = try LibraryName.apply(before.body, name: "Night Shift")
        try renamed.write(to: ownerRoot.appendingPathComponent("library.json"))
        let putsBefore = await store.recordedPuts().count
        do {
            _ = try await owner.publishLibrary(renamed, role: .member)
            XCTFail("member")
        } catch SyncFailure.notAllowed {}
        let putsAfterRefusal = await store.recordedPuts().count
        XCTAssertEqual(putsAfterRefusal, putsBefore)

        _ = try await owner.publishLibrary(renamed, role: .admin)
        let puts = await store.recordedPuts()
        let publish = puts.last
        XCTAssertEqual(publish?.key, "library.json")
        XCTAssertEqual(publish?.ifMatch, before.etag)
        XCTAssertNil(publish?.ifNoneMatch)

        let pulled = try await member.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_020))
        XCTAssertTrue(pulled.downloaded.contains("library.json"))
        let arrived = try JSONSerialization.jsonObject(with: Data(contentsOf: memberRoot.appendingPathComponent("library.json"))) as? [String: Any]
        XCTAssertEqual(arrived?["name"] as? String, "Night Shift")
    }

    func testRenameDuringSyncKeepsTheNameLocallyInTheBucketAndOnTheOtherMac() async throws {
        let store = MemoryObjectStore()
        let ownerRoot = try TestLibrary.makeRoot()
        let memberRoot = try TestLibrary.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: ownerRoot)
            try? FileManager.default.removeItem(at: memberRoot)
        }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: ownerRoot)
        let owner = BucketSyncEngine(store: store, root: ownerRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let published = try await store.get("library.json")
        try published.body.write(to: memberRoot.appendingPathComponent("library.json"))
        let renamed = try LibraryName.apply(published.body, name: "Night Shift")
        let racing = RenameDuringGet(inner: store, root: ownerRoot, renamed: renamed)
        let engine = BucketSyncEngine(store: racing, root: ownerRoot, merger: ClosureMerger { _, local, _ in local }, manifest: await owner.currentManifest(), appVersion: "0.3.5")
        _ = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_020))

        let local = try JSONSerialization.jsonObject(with: Data(contentsOf: ownerRoot.appendingPathComponent("library.json"))) as? [String: Any]
        let remote = try JSONSerialization.jsonObject(with: try await store.get("library.json").body) as? [String: Any]
        XCTAssertEqual(local?["name"] as? String, "Night Shift")
        XCTAssertEqual(remote?["name"] as? String, "Night Shift")

        let member = BucketSyncEngine(store: store, root: memberRoot, merger: ClosureMerger { _, local, _ in local }, manifest: await owner.currentManifest(), appVersion: "0.3.5")
        _ = try await member.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_040))
        let arrived = try JSONSerialization.jsonObject(with: Data(contentsOf: memberRoot.appendingPathComponent("library.json"))) as? [String: Any]
        XCTAssertEqual(arrived?["name"] as? String, "Night Shift")
    }

    func testRemoteLibraryEditKeepsTheLocalName() async throws {
        let store = MemoryObjectStore()
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (key, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let owner = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let published = try await store.get("library.json")
        let renamed = try LibraryName.apply(published.body, name: "Night Shift")
        try renamed.write(to: root.appendingPathComponent("library.json"))
        guard var body = TeamDocument.parse(signed.canonical) else {
            XCTFail("team")
            return
        }
        body.generation += 1
        body.capGB = 8
        let edited = try TeamFile.write(try TeamDocument.sign(body, key: key), into: published.body)
        await store.seed("library.json", body: edited)
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_030))

        let local = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("library.json"))) as? [String: Any]
        let remoteBody = try await store.get("library.json").body
        let remote = try JSONSerialization.jsonObject(with: remoteBody) as? [String: Any]
        XCTAssertEqual(local?["name"] as? String, "Night Shift")
        XCTAssertEqual(remote?["name"] as? String, "Night Shift")
        let team = TeamFile.read(remoteBody).flatMap { TeamDocument.parse($0.canonical) }
        XCTAssertEqual(team?.generation, 2)
        XCTAssertEqual(team?.capGB, 8)
    }

    func testSyncPassRecordsTheRemoteLibraryEtag() async throws {
        let store = MemoryObjectStore()
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let owner = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let published = try await store.get("library.json")
        await store.seed("library.json", body: published.body, etag: "8c1247e3c1e8a4875a1c92ce08cf705b")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_020))
        let manifest = await owner.currentManifest()
        XCTAssertEqual(manifest.entries["library.json"]?.etag, "8c1247e3c1e8a4875a1c92ce08cf705b")
        XCTAssertEqual(manifest.entries["library.json"]?.digest, Digests.sha256Hex(published.body))
        XCTAssertNotEqual(published.etag, "8c1247e3c1e8a4875a1c92ce08cf705b")
    }

    func testStaleEtagRenameAppliesTheNameOntoTheRemoteBody() async throws {
        let store = MemoryObjectStore()
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let owner = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let stale = await owner.currentManifest().entries["library.json"]?.etag
        let published = try await store.get("library.json")
        let remote = try LibraryName.apply(published.body, name: "Studio Library")
        await store.seed("library.json", body: remote, etag: "8c1247e3c1e8a4875a1c92ce08cf705b")
        let stillStale = await owner.currentManifest().entries["library.json"]?.etag
        XCTAssertEqual(stillStale, stale)
        let local = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let renamed = try LibraryName.apply(local, name: "Night Shift")
        let putsBefore = await store.recordedPuts().count
        do {
            _ = try await owner.publishLibrary(renamed, role: .member)
            XCTFail("member")
        } catch SyncFailure.notAllowed {}
        let putsAfterRefusal = await store.recordedPuts().count
        XCTAssertEqual(putsAfterRefusal, putsBefore)
        XCTAssertEqual(LibraryName.read(try Data(contentsOf: root.appendingPathComponent("library.json"))), "Studio")

        let publishedBody = try await owner.publishLibrary(renamed, role: .admin)
        let fresh = await store.recordedPuts().dropFirst(putsBefore)
        XCTAssertEqual(fresh.first?.ifMatch, stale)
        XCTAssertEqual(fresh.last?.ifMatch, "8c1247e3c1e8a4875a1c92ce08cf705b")
        let stored = try await store.get("library.json")
        XCTAssertEqual(LibraryName.read(stored.body), "Night Shift")
        XCTAssertEqual(LibraryName.read(publishedBody), "Night Shift")
        XCTAssertEqual(canonical(stored.body), canonical(remote))
        let manifest = await owner.currentManifest()
        XCTAssertEqual(manifest.entries["library.json"]?.etag, stored.etag)
        XCTAssertEqual(manifest.entries["library.json"]?.digest, Digests.sha256Hex(stored.body))

        try publishedBody.write(to: root.appendingPathComponent("library.json"), options: .atomic)
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_040))
        let settledLocal = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let settledRemote = try await store.get("library.json")
        XCTAssertEqual(LibraryName.read(settledLocal), "Night Shift")
        XCTAssertEqual(LibraryName.read(settledRemote.body), "Night Shift")
    }

    func testStaleReloadDoesNotResetTheName() {
        XCTAssertEqual(LibraryName.kept(current: "Night Shift", reloaded: "Studio", live: "Night Shift"), "Night Shift")
        XCTAssertEqual(LibraryName.kept(current: "Studio", reloaded: "Night Shift", live: "Night Shift"), "Night Shift")
        XCTAssertEqual(LibraryName.kept(current: "Whaaaaa", reloaded: "Studio", live: "Studio", pending: "Whaaaaa"), "Whaaaaa")
        XCTAssertEqual(LibraryName.kept(current: "Whaaaaa", reloaded: "Whaaaaa", live: "Whaaaaa", pending: "Whaaaaa"), "Whaaaaa")
    }

    func testRenameProblemsNameTheCause() {
        XCTAssertEqual(RenameProblem.message(for: SyncFailure.notAllowed), "Only an owner or admin can rename this library")
        XCTAssertEqual(RenameProblem.message(for: S3Error.preconditionFailed), "The bucket rejected the rename (412). Try again.")
        XCTAssertEqual(RenameProblem.message(for: S3Error.notFound), "The library is not in the bucket yet.")
        XCTAssertEqual(RenameProblem.message(for: S3Error.status(503, "down")), "The bucket rejected the rename (503).")
        XCTAssertEqual(RenameProblem.message(for: S3Error.badResponse), "The bucket sent a bad response.")
        XCTAssertEqual(RenameProblem.message(for: LibraryNameError.malformed), "The library file could not be read.")
        XCTAssertEqual(RenameProblem.message(for: URLError(.cannotConnectToHost)), "Couldn't reach the bucket.")
    }

    func testTwoRenamesBackToBackKeepTheETag() async throws {
        let store = MemoryObjectStore()
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let owner = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let original = try await store.get("library.json")
        let first = try LibraryName.apply(original.body, name: "Whaaaaa")
        let published = try await owner.publishLibrary(first, role: .admin)
        let mid = try await store.get("library.json")
        let midManifest = await owner.currentManifest()
        XCTAssertEqual(LibraryName.read(mid.body), "Whaaaaa")
        XCTAssertEqual(midManifest.entries["library.json"]?.etag, mid.etag)
        let second = try LibraryName.apply(published, name: "Night Shift")
        let putsBefore = await store.recordedPuts().count
        _ = try await owner.publishLibrary(second, role: .admin)
        let fresh = await store.recordedPuts().dropFirst(putsBefore)
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(fresh.first?.ifMatch, mid.etag)
        let live = try await store.get("library.json")
        let liveManifest = await owner.currentManifest()
        XCTAssertEqual(LibraryName.read(live.body), "Night Shift")
        XCTAssertEqual(liveManifest.entries["library.json"]?.etag, live.etag)
        XCTAssertEqual(canonical(live.body), canonical(original.body))
    }

    func testRenameDuringSyncDoesNotLoseTheETag() async throws {
        let store = MemoryObjectStore()
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let seeded = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await seeded.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let manifest = await seeded.currentManifest()
        let gate = PassGate()
        let racing = StallingObjectStore(inner: store, gate: gate)
        let owner = BucketSyncEngine(store: racing, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: manifest, appVersion: "0.3.5")
        let original = try await store.get("library.json")
        let first = try LibraryName.apply(original.body, name: "Whaaaaa")
        let syncing = Task { try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_020)) }
        await gate.until("get")
        let published = try await owner.publishLibrary(first, role: .admin)
        let mid = try await store.get("library.json")
        XCTAssertEqual(LibraryName.read(mid.body), "Whaaaaa")
        await gate.release("get")
        await gate.until("list")
        let second = try LibraryName.apply(published, name: "Night Shift")
        let putsBefore = await store.recordedPuts().count
        _ = try await owner.publishLibrary(second, role: .admin)
        let fresh = await store.recordedPuts().dropFirst(putsBefore)
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(fresh.first?.ifMatch, mid.etag)
        await gate.release("list")
        _ = try await syncing.value
        let live = try await store.get("library.json")
        let liveManifest = await owner.currentManifest()
        XCTAssertEqual(LibraryName.read(live.body), "Night Shift")
        XCTAssertEqual(liveManifest.entries["library.json"]?.etag, live.etag)
        XCTAssertEqual(canonical(live.body), canonical(original.body))
    }

    private func canonical(_ data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let team = object?["team"] as? [String: Any]
        return team?["canonical"] as? String
    }
}

/// Writes the renamed library while `library.json` is being fetched, the same window as a rename during `syncPass`.
private final class RenameDuringGet: ObjectStore, @unchecked Sendable {
    private let inner: MemoryObjectStore
    private let root: URL
    private let renamed: Data
    private nonisolated(unsafe) var armed = true

    init(inner: MemoryObjectStore, root: URL, renamed: Data) {
        self.inner = inner
        self.root = root
        self.renamed = renamed
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        if key == "library.json", armed {
            armed = false
            try renamed.write(to: root.appendingPathComponent("library.json"), options: .atomic)
        }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

/// The sync pass's first `library.json` get returns the body from before a rename, and the following list waits until a second rename has been published.
private actor PassGate {
    private var claimed: Set<String> = []
    private var arrived: Set<String> = []
    private var released: Set<String> = []
    private var arrivalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func until(_ id: String) async {
        if arrived.contains(id) { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            arrivalWaiters[id, default: []].append(cont)
        }
    }

    func release(_ id: String) {
        released.insert(id)
        releaseWaiters[id]?.forEach { $0.resume() }
        releaseWaiters[id] = nil
    }

    fileprivate func claim(_ id: String) -> Bool {
        guard !claimed.contains(id) else { return false }
        claimed.insert(id)
        return true
    }

    fileprivate func arrive(_ id: String) async {
        arrived.insert(id)
        arrivalWaiters[id]?.forEach { $0.resume() }
        arrivalWaiters[id] = nil
        if released.contains(id) { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            releaseWaiters[id, default: []].append(cont)
        }
    }
}

private final class StallingObjectStore: ObjectStore, @unchecked Sendable {
    private let inner: MemoryObjectStore
    private let gate: PassGate

    init(inner: MemoryObjectStore, gate: PassGate) {
        self.inner = inner
        self.gate = gate
    }

    func list(prefix: String) async throws -> [ObjectHead] {
        if await gate.claim("list") {
            await gate.arrive("list")
        }
        return try await inner.list(prefix: prefix)
    }

    func get(_ key: String) async throws -> ObjectGet {
        if key == "library.json", await gate.claim("get") {
            let snapshot = try await inner.get(key)
            await gate.arrive("get")
            return snapshot
        }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}
