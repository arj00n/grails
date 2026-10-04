import Foundation
import Network
import Security

public protocol TokenStorage: Sendable {
    func token() -> String
    func regenerate() -> String
}

public enum TokenGenerator {
    public static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String
    public init(_ token: String = TokenGenerator.make()) { value = token }
    public func token() -> String { lock.lock(); defer { lock.unlock() }; return value }
    public func regenerate() -> String { lock.lock(); defer { lock.unlock() }; value = TokenGenerator.make(); return value }
}

/// The pairing token lives in the login Keychain so it survives app updates and never sits in a plain file.
public final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let service: String
    private let account = "api-token"
    public init(service: String = "in.justswish.stash") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func token() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty { return s }
        return regenerate()
    }

    @discardableResult
    public func regenerate() -> String {
        let t = TokenGenerator.make()
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(t.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        return t
    }
}

/// HTTP API on 127.0.0.1 for the browser extension. Every request needs the bearer token; browser origins other than
/// extensions are refused, so a web page can't talk to it even if it guesses the port.
public final class LocalAPIServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47823
    public static let version = "0.1"

    private let service: CaptureService
    private let tokens: TokenStorage
    private let queue = DispatchQueue(label: "in.justswish.stash.api")
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0
    private let maxBody: Int

    public init(service: CaptureService, tokens: TokenStorage, maxBody: Int = 64 * 1024 * 1024) {
        self.service = service; self.tokens = tokens; self.maxBody = maxBody
    }

    /// Starts listening on loopback. `port` 0 picks a free port (tests); otherwise tries `port`…`port+9`.
    @discardableResult
    public func start(port: UInt16 = LocalAPIServer.defaultPort) async throws -> UInt16 {
        let candidates: [UInt16] = port == 0 ? [0] : Array(port...(port &+ 9))
        var lastError: Error = NWError.posix(.EADDRINUSE)
        for p in candidates {
            do {
                let bound = try await bind(p)
                self.port = bound
                return bound
            } catch { lastError = error }
        }
        throw lastError
    }

    private func bind(_ p: UInt16) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: p) ?? .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { cont in
            let box = ResumeOnce(cont)
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: box.resume(.success(l.port?.rawValue ?? p))
                case .failed(let e): box.resume(.failure(e))
                case .cancelled: box.resume(.failure(CancellationError()))
                default: break
                }
            }
            l.start(queue: queue)
        }
        listener = l
        return boundPort
    }

    public func stop() { listener?.cancel(); listener = nil }

    private final class ResumeOnce: @unchecked Sendable {
        private var cont: CheckedContinuation<UInt16, Error>?
        private let lock = NSLock()
        init(_ c: CheckedContinuation<UInt16, Error>) { cont = c }
        func resume(_ r: Result<UInt16, Error>) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(with: r)
        }
    }

    // MARK: Connections

    public static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a): return a.rawValue.first == 127
        case .ipv6(let a): return a == IPv6Address.loopback || a.isIPv4Mapped && (a.asIPv4?.rawValue.first == 127)
        case .name(let n, _): return n.lowercased() == "localhost"
        @unknown default: return false
        }
    }

    private func accept(_ c: NWConnection) {
        if case .hostPort(let host, _) = c.endpoint, !Self.isLoopback(host) { c.cancel(); return }
        c.start(queue: queue)
        let state = ConnectionState(parser: HTTPRequestParser(maxBody: maxBody))
        read(c, state)
    }

    private final class ConnectionState: @unchecked Sendable {
        var parser: HTTPRequestParser
        init(parser: HTTPRequestParser) { self.parser = parser }
    }

    private func read(_ c: NWConnection, _ state: ConnectionState) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { c.cancel(); return }
            if let data, !data.isEmpty {
                switch state.parser.append(data) {
                case .needMore:
                    if isComplete || error != nil { c.cancel() } else { self.read(c, state) }
                case .complete:
                    guard let req = state.parser.request else { c.cancel(); return }
                    Task {
                        let response = await self.route(req)
                        self.send(response, on: c)
                    }
                case .tooLarge: self.send(.error(413, "Request body too large"), on: c)
                case .malformed: self.send(.error(400, "Malformed request"), on: c)
                }
            } else if isComplete || error != nil {
                c.cancel()
            }
        }
    }

    private func send(_ response: HTTPResponse, on c: NWConnection) {
        c.send(content: response.serialized(), completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: Routing

    static func originAllowed(_ origin: String?) -> Bool {
        guard let origin else { return true }                 // curl, native clients
        return ["chrome-extension://", "moz-extension://", "safari-web-extension://"].contains { origin.hasPrefix($0) }
    }

    public func route(_ req: HTTPRequest) async -> HTTPResponse {
        let origin = req.header("origin")
        guard Self.originAllowed(origin) else { return .error(403, "Origin not allowed") }
        var cors: [String: String] = [:]
        if let origin {
            cors = ["Access-Control-Allow-Origin": origin, "Vary": "Origin",
                    "Access-Control-Allow-Headers": "authorization, content-type",
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Max-Age": "600"]
        }
        var response = await handle(req)
        for (k, v) in cors { response.headers[k] = v }
        return response
    }

    private func handle(_ req: HTTPRequest) async -> HTTPResponse {
        if req.method == "OPTIONS" { return HTTPResponse(status: 204) }
        guard let auth = req.header("authorization"), auth.hasPrefix("Bearer "),
              Self.constantTimeEquals(String(auth.dropFirst(7)), tokens.token()) else { return .error(401, "Missing or invalid token") }

        switch (req.method, req.path) {
        case ("GET", "/api/v1/ping"):
            struct Ping: Encodable { let ok = true; let app = "Stash"; let version: String; let library: String }
            return .json(200, Ping(version: Self.version, library: await service.libraryName))
        case ("GET", "/api/v1/collections"):
            return .json(200, await service.collections())
        case ("POST", "/api/v1/items"):
            guard let save = try? JSONDecoder().decode(SaveRequest.self, from: req.body) else { return .error(400, "Body must be JSON: { mediaUrl?, pageUrl?, title?, dataBase64?, collectionId?, tags? }") }
            do {
                let result = try await service.save(save)
                return .json(result.duplicate ? 200 : 201, result)
            } catch let e as CaptureError {
                switch e {
                case .nothingToSave, .badURL, .unsupported: return .error(400, e.localizedDescription)
                case .downloadFailed: return .error(502 as Int, e.localizedDescription)
                case .noLibrary: return .error(503, e.localizedDescription)
                }
            } catch { return .error(500, error.localizedDescription) }
        case ("POST", "/api/v1/imports"):
            guard let r = try? JSONDecoder().decode(BoardImportRequest.self, from: req.body), r.isActionable else {
                return .error(400, "Body must be JSON: { source: \"pinterest\", name, url?, pinIds: [...] } or { source: \"x\", url }")
            }
            do { return .json(202, try await service.importBoard(r)) }
            catch let e as CaptureError {
                switch e { case .noLibrary: return .error(503, e.localizedDescription); default: return .error(400, e.localizedDescription) }
            } catch { return .error(500, error.localizedDescription) }
        case (_, "/api/v1/ping"), (_, "/api/v1/collections"), (_, "/api/v1/items"), (_, "/api/v1/imports"):
            return .error(405, "Method not allowed")
        default:
            return .error(404, "Not found")
        }
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
