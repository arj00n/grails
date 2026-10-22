import Foundation
import GrailsSync

struct RecordedPut: Equatable, Sendable {
    var key: String
    var body: Data
    var ifMatch: String?
    var ifNoneMatch: String?
}

actor MemoryObjectStore: ObjectStore {
    struct Counts: Equatable, Sendable {
        var lists: Int
        var gets: Int
        var puts: Int
        var deletes: Int
    }

    private struct Object {
        var body: Data
        var etag: String
        var modified: Date?
    }

    private var objects: [String: Object] = [:]
    private var lists = 0
    private var gets = 0
    private var puts = 0
    private var deletes = 0
    private var recorded: [RecordedPut] = []

    func seed(_ key: String, body: Data, etag: String? = nil, modified: Date? = nil) {
        objects[key] = Object(body: body, etag: etag ?? Digests.sha256Hex(body), modified: modified)
    }

    func counts() -> Counts { Counts(lists: lists, gets: gets, puts: puts, deletes: deletes) }

    func recordedPuts() -> [RecordedPut] { recorded }

    func keys() -> [String] { objects.keys.sorted() }

    func body(_ key: String) -> Data? { objects[key]?.body }

    func list(prefix: String) async throws -> [ObjectHead] {
        lists += 1
        return objects.keys.filter { $0.hasPrefix(prefix) }.sorted().map { key in
            ObjectHead(key: key, etag: objects[key]!.etag, size: Int64(objects[key]!.body.count), modified: objects[key]!.modified)
        }
    }

    func get(_ key: String) async throws -> ObjectGet {
        gets += 1
        guard let object = objects[key] else { throw S3Error.notFound }
        return ObjectGet(body: object.body, etag: object.etag)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        _ = contentType
        puts += 1
        recorded.append(RecordedPut(key: key, body: body, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch))
        if ifNoneMatch == "*", objects[key] != nil { throw S3Error.preconditionFailed }
        if let ifMatch, objects[key]?.etag != ifMatch { throw S3Error.preconditionFailed }
        let etag = Digests.sha256Hex(body)
        let modified = objects[key]?.modified
        objects[key] = Object(body: body, etag: etag, modified: modified)
        return etag
    }

    func delete(_ key: String) async throws {
        deletes += 1
        objects[key] = nil
    }
}

actor MemorySnapshots: SnapshotDestination {
    private var objects: [String: Data] = [:]

    func list(prefix: String) async throws -> [ObjectHead] {
        objects.keys.filter { $0.hasPrefix(prefix) }.sorted().map { key in
            let body = objects[key]!
            return ObjectHead(key: key, etag: Digests.sha256Hex(body), size: Int64(body.count))
        }
    }

    func put(_ key: String, body: Data) async throws {
        objects[key] = body
    }

    func keys() -> [String] { objects.keys.sorted() }

    func body(_ key: String) -> Data? { objects[key] }
}

enum TestLibrary {
    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grails-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func owner(email: String = "arjun@studio.com", minAppVersion: String = TeamBody.defaultMinAppVersion, capGB: Int = TeamBody.defaultCapGB) throws -> (DeviceKey, SignedTeam) {
        let key = DeviceKey()
        let body = TeamBody(
            generation: 1,
            ownerEmail: email,
            ownerPublicKey: key.publicKey,
            capGB: capGB,
            minAppVersion: minAppVersion,
            members: [TeamMember(email: email, role: .owner)]
        )
        return (key, try TeamDocument.sign(body, key: key))
    }

    static func writeLibrary(_ signed: SignedTeam, root: URL) throws {
        let data = try TeamFile.write(signed, into: Data(#"{"name":"Studio"}"#.utf8))
        try data.write(to: root.appendingPathComponent("library.json"))
    }
}
