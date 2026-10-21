import Crypto
import Foundation

enum Hex {
    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let extra = (4 - padded.count % 4) % 4
        padded += String(repeating: "=", count: extra)
        return Data(base64Encoded: padded)
    }
}

public enum Digests {
    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    public static func hex(_ data: Data) -> String { Hex.encode(data) }

    public static func sha256Hex(_ data: Data) -> String { hex(sha256(data)) }

    static func hmacSHA256(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    /// PBKDF2-HMAC-SHA256. The invite code is only six digits, so the blob header carries a high iteration count.
    public static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int = 32) -> Data {
        precondition(iterations > 0 && length > 0)
        let blockCount = (length + 31) / 32
        var out = [UInt8]()
        out.reserveCapacity(blockCount * 32)
        for block in 1...blockCount {
            var message = [UInt8](salt)
            message.append(UInt8((block >> 24) & 0xff))
            message.append(UInt8((block >> 16) & 0xff))
            message.append(UInt8((block >> 8) & 0xff))
            message.append(UInt8(block & 0xff))
            var u = [UInt8](hmacSHA256(key: password, message: Data(message)))
            var t = u
            if iterations > 1 {
                for _ in 2...iterations {
                    u = [UInt8](hmacSHA256(key: password, message: Data(u)))
                    for index in t.indices { t[index] ^= u[index] }
                }
            }
            out.append(contentsOf: t)
        }
        return Data(out.prefix(length))
    }
}
