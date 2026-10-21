import Foundation
import GrailsEndpoints
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uploads a sealed invite to the build's site (`GrailsEndpoints.site`) and reads it back. The 6-digit code never leaves the Mac.
/// A build with no site has no relay: publish, resolve and remove do nothing, and invites stay long `grails://j/` links.
public enum InviteRelay {
    public static let origin: URL? = GrailsEndpoints.site
    public static let maxBlobLength = 4096
    public static let timeout: TimeInterval = 8

    public struct Published: Equatable, Sendable {
        public var id: String
        public var url: URL
    }

    public struct Resolved: Equatable, Sendable {
        public var inviteID: String
        public var blob: String
    }

    public typealias Exchange = @Sendable (URLRequest) async -> (Int, Data)?

    public static func live(_ request: URLRequest) async -> (Int, Data)? {
        var request = request
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let transport = HTTPTransport()
        guard let (data, response) = try? await transport.data(for: request) else { return nil }
        return (response.statusCode, data)
    }

    /// The short page for an id this relay minted. Twelve characters is the id this service issues.
    public static func link(id: String, origin: URL) -> URL {
        origin.appendingPathComponent("i").appendingPathComponent(id)
    }

    public static func isShortID(_ id: String) -> Bool {
        guard (8...22).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.shortID.contains(scalar)
        }
    }

    public static func shortID(in text: String) -> String? {
        for part in text.split(whereSeparator: \.isWhitespace) {
            let trimmed = part.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'.,"))
            if let url = URL(string: String(trimmed)), let id = shortID(in: url) { return id }
        }
        return nil
    }

    public static func shortID(in url: URL, origin: URL? = InviteRelay.origin) -> String? {
        if url.scheme?.lowercased() == "grails", url.host?.lowercased() == "i" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return isShortID(id) ? id : nil
        }
        guard let origin, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.lowercased() == origin.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "i", isShortID(parts[1]) else { return nil }
        return parts[1]
    }

    /// Posts the sealed blob. A failure returns nil so the caller can share the compact link instead.
    public static func publish(blob: String, exp: TimeInterval, id: String, origin: URL? = InviteRelay.origin, exchange: Exchange = live) async -> Published? {
        guard let origin, InviteBlob.isSealed(blob), blob.count <= maxBlobLength, !id.isEmpty else { return nil }
        guard var request = request(origin: origin, path: "/api/invite", method: "POST") else { return nil }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(PublishBody(blob: blob, exp: exp, id: id))
        guard let (status, data) = await exchange(request), status == 201,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              isShortID(reply.id) else { return nil }
        return Published(id: reply.id, url: link(id: reply.id, origin: origin))
    }

    public static func resolve(id: String, origin: URL? = InviteRelay.origin, exchange: Exchange = live) async -> Resolved? {
        guard let origin, isShortID(id), let request = request(origin: origin, path: "/api/invite/\(id)", method: "GET"),
              let (status, data) = await exchange(request), status == 200,
              let reply = try? JSONDecoder().decode(ReadReply.self, from: data),
              InviteBlob.isSealed(reply.blob) else { return nil }
        let inviteID = InviteBlob.id(in: reply.blob) ?? reply.id
        guard !inviteID.isEmpty else { return nil }
        return Resolved(inviteID: inviteID, blob: reply.blob)
    }

    /// Drops the stored blob after a successful redeem. A network failure does not fail the join.
    public static func remove(id: String, origin: URL? = InviteRelay.origin, exchange: Exchange = live) async {
        guard let origin, isShortID(id), let request = request(origin: origin, path: "/api/invite/\(id)", method: "DELETE") else { return }
        _ = await exchange(request)
    }

    private static func request(origin: URL, path: String, method: String) -> URLRequest? {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}

private extension CharacterSet {
    static let shortID = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
}

private struct PublishBody: Encodable {
    var blob: String
    var exp: TimeInterval
    var id: String
}

private struct Reply: Decodable {
    var id: String
}

private struct ReadReply: Decodable {
    var blob: String
    var id: String
}
