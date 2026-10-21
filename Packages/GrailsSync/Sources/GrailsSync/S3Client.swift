import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ObjectHead: Equatable, Sendable, Codable {
    public var key: String
    public var etag: String
    public var size: Int64

    public init(key: String, etag: String, size: Int64) {
        self.key = key
        self.etag = etag
        self.size = size
    }
}

public struct ObjectGet: Equatable, Sendable {
    public var body: Data
    public var etag: String

    public init(body: Data, etag: String) {
        self.body = body
        self.etag = etag
    }
}

public enum S3Error: Error, Equatable {
    case preconditionFailed
    case notFound
    case status(Int, String)
    case badResponse
}

public protocol ObjectStore: Sendable {
    func list(prefix: String) async throws -> [ObjectHead]
    func get(_ key: String) async throws -> ObjectGet
    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String
    func delete(_ key: String) async throws
}

/// Snapshot writes can add objects and cannot remove them.
public protocol SnapshotDestination: Sendable {
    func list(prefix: String) async throws -> [ObjectHead]
    func put(_ key: String, body: Data) async throws
}

public struct S3Location: Equatable, Sendable {
    public var endpoint: URL
    public var bucket: String
    public var region: String
    /// Prepended to every key. Tests use `_test/<id>/`. Production uses `""`.
    public var keyPrefix: String

    public init(endpoint: URL, bucket: String, region: String, keyPrefix: String = "") {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.keyPrefix = keyPrefix
    }
}

public struct S3Credentials: Equatable, Sendable {
    public var accessKeyId: String
    public var secretAccessKey: String

    public init(accessKeyId: String, secretAccessKey: String) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
    }
}

extension S3Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "S3Credentials(accessKeyId: \(accessKeyId), secretAccessKey: <redacted>)" }
    public var debugDescription: String { description }
}

public enum HTTPTimeouts {
    /// Idle time between packets. A QUIC connection can reset this without delivering a body, so `stall` is the backstop.
    public static let request: TimeInterval = 60
    /// No request or response bytes for this long fails the transfer. A file that keeps moving may still run until `resource`.
    public static let stall: TimeInterval = 90
    /// Covers the 200 MB file cap on a slow link. A pass that hits it fails and retries.
    public static let resource: TimeInterval = 40 * 60
}

/// URLSession is not Sendable on Linux. The wrapper keeps the client shareable across the sync actor.
public final class HTTPTransport: @unchecked Sendable {
    public let session: URLSession

    /// The shared session's stall clock. A test session passes its own delegate.
    public static let loader = TransferDelegate(stall: HTTPTimeouts.stall)

    /// `URLSession.shared` writes GETs into `~/Library/Caches/xyz.arjoon.grails/Cache.db`. A cached `library.json` came back with the old body and etag, so each rename retry was a 412 and the sync pass restored the old name.
    public static let uncached: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = HTTPTimeouts.request
        config.timeoutIntervalForResource = HTTPTimeouts.resource
        let session = URLSession(configuration: config, delegate: loader, delegateQueue: nil)
        loader.start(session: session, every: .seconds(5), tolerance: .seconds(1))
        return session
    }()

    public init(session: URLSession = HTTPTransport.uncached) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let loader = session.delegate as? TransferDelegate {
            let box = TransferTaskBox()
            return try await withTaskCancellationHandler {
                try await loader.load(session: session, request: request, box: box)
            } onCancel: {
                box.cancel()
            }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw S3Error.badResponse }
        return (data, http)
    }

    public func cancelInFlight() {
        (session.delegate as? TransferDelegate)?.cancelAll()
    }
}

/// Holds the task so a cancelled sync pass can stop the socket before `URLSession` notices.
public final class TransferTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func assign(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let cancelled = cancelled
        lock.unlock()
        if cancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

/// Watches request and response bytes. `timeoutIntervalForRequest` is idle time on the socket, and a QUIC session can keep that idle timer alive without a body. This clock fails the task when no bytes have moved for `stall`.
public final class TransferDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public let stall: TimeInterval
    public var now: @Sendable () -> Date
    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private var watch: Task<Void, Never>?

    public init(stall: TimeInterval = HTTPTimeouts.stall, now: @escaping @Sendable () -> Date = { Date() }) {
        self.stall = stall
        self.now = now
    }

    private struct Job {
        var task: URLSessionTask?
        var data = Data()
        var response: HTTPURLResponse?
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var last: TimeInterval
        var stalled = false
    }

    public func note(_ id: Int, at time: TimeInterval) {
        lock.lock()
        if jobs[id] == nil {
            jobs[id] = Job(last: time)
        } else {
            jobs[id]?.last = time
        }
        lock.unlock()
    }

    public func staleIDs(at time: TimeInterval) -> Set<Int> {
        lock.lock()
        defer { lock.unlock() }
        return Set(jobs.compactMap { time - $0.value.last >= stall ? $0.key : nil })
    }

    public func start(session: URLSession, every: Duration, tolerance: Duration) {
        watch?.cancel()
        watch = Task { [weak self, weak session] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every, tolerance: tolerance)
                guard let self, session != nil else { return }
                self.cancelStale(at: self.now())
            }
        }
    }

    deinit { watch?.cancel() }

    func load(session: URLSession, request: URLRequest, box: TransferTaskBox) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
            let task = session.dataTask(with: request)
            box.assign(task)
            let id = task.taskIdentifier
            lock.lock()
            var job = jobs[id] ?? Job(last: now().timeIntervalSince1970)
            job.task = task
            job.continuation = cont
            job.last = now().timeIntervalSince1970
            jobs[id] = job
            lock.unlock()
            task.resume()
        }
    }

    public func cancelAll() {
        lock.lock()
        let tasks = jobs.values.compactMap(\.task)
        lock.unlock()
        for task in tasks { task.cancel() }
    }

    private func cancelStale(at date: Date) {
        let time = date.timeIntervalSince1970
        lock.lock()
        let stale = jobs.compactMap { time - $0.value.last >= stall ? $0.key : nil }
        for id in stale { jobs[id]?.stalled = true }
        let tasks = stale.compactMap { jobs[$0]?.task }
        lock.unlock()
        for task in tasks { task.cancel() }
    }

    private func touch(_ id: Int) {
        note(id, at: now().timeIntervalSince1970)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        touch(dataTask.taskIdentifier)
        if let http = response as? HTTPURLResponse {
            lock.lock()
            jobs[dataTask.taskIdentifier]?.response = http
            lock.unlock()
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        touch(dataTask.taskIdentifier)
        lock.lock()
        jobs[dataTask.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        touch(task.taskIdentifier)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        lock.lock()
        let job = jobs.removeValue(forKey: id)
        lock.unlock()
        guard let job, let continuation = job.continuation else { return }
        if job.stalled {
            continuation.resume(throwing: TransferStall())
            return
        }
        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let response = job.response else {
            continuation.resume(throwing: S3Error.badResponse)
            return
        }
        continuation.resume(returning: (job.data, response))
    }
}

public protocol SyncStoppable: Sendable {
    func cancelInFlight() async
}

/// Deletes the shared-session disk cache once per app version. Later launches of that version leave the folder alone.
public enum URLCacheSweep {
    public static let defaultsKey = "urlCacheSwept"
    /// The app's own cache folder. A fork with its own bundle id sweeps its own.
    public static let bundleID = Bundle.main.bundleIdentifier ?? "xyz.arjoon.grails"
    public static let fileNames = ["Cache.db", "Cache.db-wal", "Cache.db-shm", "Cache.db-journal"]

    public static func token(version: String, build: String) -> String { "\(version) (\(build))" }

    /// Removes `Cache.db` and its sqlite sidecars under `cachesDirectory/<bundle id>`. Returns false when this version already swept, or when a file is still there.
    @discardableResult
    public static func clearOnce(cachesDirectory: URL, version: String, build: String, defaults: UserDefaults, fileManager: FileManager = .default) -> Bool {
        let token = token(version: version, build: build)
        if defaults.string(forKey: defaultsKey) == token { return false }
        let dir = cachesDirectory.appendingPathComponent(bundleID, isDirectory: true)
        for name in fileNames {
            let url = dir.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        let stuck = fileNames.contains { fileManager.fileExists(atPath: dir.appendingPathComponent($0).path) }
        if stuck { return false }
        defaults.set(token, forKey: defaultsKey)
        return true
    }
}

public struct S3Client: ObjectStore, SnapshotDestination, SyncStoppable, Sendable {
    public var location: S3Location
    public var credentials: S3Credentials
    public var transport: HTTPTransport
    public var now: @Sendable () -> Date

    public init(location: S3Location, credentials: S3Credentials, session: URLSession = HTTPTransport.uncached, now: @escaping @Sendable () -> Date = { Date() }) {
        self.location = location
        self.credentials = credentials
        self.transport = HTTPTransport(session: session)
        self.now = now
    }

    public func cancelInFlight() async {
        transport.cancelInFlight()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            transport.session.reset { cont.resume() }
        }
    }

    public func list(prefix: String) async throws -> [ObjectHead] {
        var token: String?
        var out: [ObjectHead] = []
        let fullPrefix = location.keyPrefix + prefix
        repeat {
            var items = [
                URLQueryItem(name: "list-type", value: "2"),
                URLQueryItem(name: "prefix", value: fullPrefix),
            ]
            if let token { items.append(URLQueryItem(name: "continuation-token", value: token)) }
            let (data, _) = try await send(method: "GET", key: nil, query: items, body: Data(), extra: [:])
            let page = try ListBucketXML.parse(data)
            out += page.objects.compactMap { head in
                guard head.key.hasPrefix(location.keyPrefix) else { return nil }
                var copy = head
                copy.key = String(head.key.dropFirst(location.keyPrefix.count))
                return copy
            }
            token = page.truncated ? page.token : nil
        } while token != nil
        return out
    }

    public func get(_ key: String) async throws -> ObjectGet {
        let (data, response) = try await send(method: "GET", key: location.keyPrefix + key, query: [], body: Data(), extra: [:])
        return ObjectGet(body: data, etag: Self.cleanETag(response.value(forHTTPHeaderField: "ETag") ?? ""))
    }

    public func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        var extra = ["content-type": contentType]
        if let ifMatch { extra["if-match"] = "\"\(Self.cleanETag(ifMatch))\"" }
        if let ifNoneMatch { extra["if-none-match"] = ifNoneMatch }
        let (_, response) = try await send(method: "PUT", key: location.keyPrefix + key, query: [], body: body, extra: extra)
        let header = response.value(forHTTPHeaderField: "ETag") ?? ""
        return header.isEmpty ? Digests.sha256Hex(body) : Self.cleanETag(header)
    }

    public func put(_ key: String, body: Data) async throws {
        _ = try await put(key, body: body, contentType: Self.contentType(key), ifMatch: nil, ifNoneMatch: nil)
    }

    public func delete(_ key: String) async throws {
        _ = try await send(method: "DELETE", key: location.keyPrefix + key, query: [], body: Data(), extra: [:])
    }

    public func createBucket() async throws {
        _ = try await send(method: "PUT", key: nil, query: [], body: Data(), extra: [:], bucketOnly: true)
    }

    func send(method: String, key: String?, query: [URLQueryItem], body: Data, extra: [String: String], bucketOnly: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: location.endpoint, resolvingAgainstBaseURL: false) else { throw S3Error.badResponse }
        let basePath = location.endpoint.path.hasSuffix("/") ? String(location.endpoint.path.dropLast()) : location.endpoint.path
        let suffix = bucketOnly ? "" : (key.map { "/" + $0 } ?? "")
        components.path = basePath + "/" + location.bucket + suffix
        if query.isEmpty {
            components.queryItems = nil
        } else {
            components.percentEncodedQuery = AWSSigV4.canonicalQuery(items: query)
        }
        guard let url = components.url else { throw S3Error.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = HTTPTimeouts.request
        request.httpBody = body.isEmpty ? nil : body
        let host = url.port.map { "\(url.host ?? ""):\($0)" } ?? (url.host ?? "")
        let date = now()
        let hash = AWSSigV4.payloadHash(body)
        var headers = extra
        headers["host"] = host
        headers["x-amz-content-sha256"] = hash
        headers["x-amz-date"] = AWSSigV4.amzDate(date).stamp
        let authorization = AWSSigV4.authorization(.init(
            method: method, url: url, headers: headers, body: body, date: date,
            region: location.region, service: "s3", accessKey: credentials.accessKeyId, secret: credentials.secretAccessKey
        ))
        for (name, value) in headers where name.lowercased() != "host" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, http) = try await transport.data(for: request)
        if http.statusCode == 412 { throw S3Error.preconditionFailed }
        if http.statusCode == 404 { throw S3Error.notFound }
        if !(200..<300).contains(http.statusCode) {
            throw S3Error.status(http.statusCode, String(data: data.prefix(400), encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    public static func contentType(_ key: String) -> String {
        let lower = key.lowercased()
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".png") { return "image/png" }
        return "application/octet-stream"
    }

    /// Bare opaque tag. List XML quotes the tag as `&quot;`, and R2 GET headers often come back weak (`W/"…"`). If-Match uses the strong form of this value.
    public static func cleanETag(_ raw: String) -> String {
        ETags.canonical(raw)
    }
}

/// One form for every ETag this process stores or compares.
/// A list response, a GET, and an older manifest do not agree on quotes or the weak `W/` prefix.
/// `W/"abc`, `"abc"`, and `&quot;abc&quot;` are the same object. Treating them as different re-downloads the library.
public enum ETags {
    public static func canonical(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("&") {
            s = s.replacingOccurrences(of: "&quot;", with: "\"")
            s = s.replacingOccurrences(of: "&#34;", with: "\"")
            s = s.replacingOccurrences(of: "&amp;", with: "&")
        }
        s = stripWeak(s)
        s = s.replacingOccurrences(of: "\"", with: "")
        s = stripWeak(s)
        return s.lowercased()
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        canonical(a) == canonical(b)
    }

    private static func stripWeak(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.count >= 2 {
            let pair = s.prefix(2)
            if pair == "W/" || pair == "w/" {
                s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        return s
    }
}

enum ListBucketXML {
    struct Page {
        var objects: [ObjectHead]
        var truncated: Bool
        var token: String?
    }

    static func parse(_ data: Data) throws -> Page {
        let text = String(data: data, encoding: .utf8) ?? ""
        var objects: [ObjectHead] = []
        let pattern = try NSRegularExpression(pattern: "<Contents>(.*?)</Contents>", options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let block = String(text[r])
            guard let key = tag("Key", in: block) else { continue }
            let etag = S3Client.cleanETag(tag("ETag", in: block) ?? "")
            let size = Int64(tag("Size", in: block) ?? "") ?? 0
            objects.append(ObjectHead(key: key, etag: etag, size: size))
        }
        let truncated = (tag("IsTruncated", in: text) ?? "").lowercased() == "true"
        let token = tag("NextContinuationToken", in: text)
        return Page(objects: objects, truncated: truncated, token: token)
    }

    private static func tag(_ name: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(name)>"), let end = text.range(of: "</\(name)>") else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
