import Foundation

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: String
    /// header names lowercased
    public var headers: [String: String]
    public var body: Data
    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String] = [:]
    public var body: Data = Data()

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    public static func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(status, ["ok": "false", "error": message])
    }

    static let reasons = [200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                          404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 500: "Internal Server Error",
                          502: "Bad Gateway", 503: "Service Unavailable"]

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Status")\r\n"
        var h = headers
        h["Content-Length"] = String(body.count)
        h["Connection"] = "close"
        for (k, v) in h.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// Incremental HTTP/1.1 request reader: feed it bytes as they arrive from the socket.
public struct HTTPRequestParser: Sendable {
    public enum Result: Equatable, Sendable {
        case needMore
        case complete
        case tooLarge
        case malformed
    }

    public static let maxHeaderBytes = 32 * 1024
    private let maxBody: Int
    private var buffer = Data()
    public private(set) var request: HTTPRequest?
    private var headerEnd: Int?
    private var contentLength = 0

    public init(maxBody: Int = 64 * 1024 * 1024) { self.maxBody = maxBody }

    public mutating func append(_ data: Data) -> Result {
        buffer.append(data)
        if headerEnd == nil {
            guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                return buffer.count > Self.maxHeaderBytes ? .malformed : .needMore
            }
            guard range.lowerBound <= Self.maxHeaderBytes else { return .malformed }
            guard let parsed = parseHead(buffer[..<range.lowerBound]) else { return .malformed }
            request = parsed.request
            contentLength = parsed.length
            headerEnd = range.upperBound
            if contentLength > maxBody { return .tooLarge }
        }
        guard let end = headerEnd else { return .needMore }
        if buffer.count - end < contentLength { return .needMore }
        request?.body = buffer.subdata(in: end..<(end + contentLength))
        return .complete
    }

    private func parseHead(_ head: Data) -> (request: HTTPRequest, length: Int)? {
        guard let text = String(data: head, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), parts[1].hasPrefix("/") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = String(parts[1])
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return nil }
        return (HTTPRequest(method: String(parts[0]).uppercased(), path: String(pieces[0]), query: pieces.count > 1 ? String(pieces[1]) : "", headers: headers, body: Data()), length)
    }
}
