import Foundation

/// AWS Signature Version 4 for S3 and Cloudflare R2. No AWS SDK.
public enum AWSSigV4 {
    public struct Input: Sendable {
        public var method: String
        public var url: URL
        public var headers: [String: String]
        public var body: Data
        public var date: Date
        public var region: String
        public var service: String
        public var accessKey: String
        public var secret: String

        public init(method: String, url: URL, headers: [String: String], body: Data, date: Date, region: String, service: String, accessKey: String, secret: String) {
            self.method = method
            self.url = url
            self.headers = headers
            self.body = body
            self.date = date
            self.region = region
            self.service = service
            self.accessKey = accessKey
            self.secret = secret
        }
    }

    public static func amzDate(_ date: Date) -> (stamp: String, day: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
        let stamp = String(format: "%@T%02d%02d%02dZ", day, parts.hour!, parts.minute!, parts.second!)
        return (stamp, day)
    }

    /// Percent-encode one path segment or query component the way SigV4 requires.
    public static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            let unreserved = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
            if unreserved {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out.append(String(format: "%%%02X", byte))
            }
        }
        return out
    }

    public static func authorization(_ input: Input) -> String {
        let (stamp, day) = amzDate(input.date)
        var headers = input.headers
        headers["x-amz-date"] = stamp
        let payload = Digests.sha256Hex(input.body)
        let canonicalHeaders = headers.map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.0 < $1.0 }
        let headerBlock = canonicalHeaders.map { "\($0.0):\($0.1)\n" }.joined()
        let signed = canonicalHeaders.map(\.0).joined(separator: ";")
        let canonicalURI = canonicalPath(input.url)
        let canonicalQuery = canonicalQueryString(input.url)
        let canonical = [
            input.method.uppercased(),
            canonicalURI,
            canonicalQuery,
            headerBlock,
            signed,
            payload,
        ].joined(separator: "\n")
        let scope = "\(day)/\(input.region)/\(input.service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            stamp,
            scope,
            Digests.sha256Hex(Data(canonical.utf8)),
        ].joined(separator: "\n")
        let signingKey = signatureKey(secret: input.secret, day: day, region: input.region, service: input.service)
        let signature = Hex.encode(Digests.hmacSHA256(key: signingKey, message: Data(stringToSign.utf8)))
        return "AWS4-HMAC-SHA256 Credential=\(input.accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(signature)"
    }

    public static func payloadHash(_ body: Data) -> String { Digests.sha256Hex(body) }

    static func canonicalPath(_ url: URL) -> String {
        let raw = url.path.isEmpty ? "/" : url.path
        let segments = raw.split(separator: "/", omittingEmptySubsequences: false).map { encode(String($0)) }
        let joined = segments.joined(separator: "/")
        return raw.hasPrefix("/") ? (joined.hasPrefix("/") ? joined : "/" + joined) : joined
    }

    /// The query string SigV4 signs. Built the same way the request URL is, so a `+` in a continuation token is `%2B` in both.
    public static func canonicalQuery(items: [URLQueryItem]) -> String {
        items.map { encode($0.name) + "=" + encode($0.value ?? "") }.sorted().joined(separator: "&")
    }

    static func canonicalQueryString(_ url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else { return "" }
        let encoded = items.map { encode($0.name) + "=" + encode($0.value ?? "") }
        return encoded.sorted().joined(separator: "&")
    }

    static func signatureKey(secret: String, day: String, region: String, service: String) -> Data {
        let dateKey = Digests.hmacSHA256(key: Data("AWS4\(secret)".utf8), message: Data(day.utf8))
        let regionKey = Digests.hmacSHA256(key: dateKey, message: Data(region.utf8))
        let serviceKey = Digests.hmacSHA256(key: regionKey, message: Data(service.utf8))
        return Digests.hmacSHA256(key: serviceKey, message: Data("aws4_request".utf8))
    }
}
