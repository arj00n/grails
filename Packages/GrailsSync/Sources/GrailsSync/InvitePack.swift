import CZlib
import Foundation

enum RawDeflate {
    /// Raw DEFLATE (no zlib wrapper). Returns nil when the output is not smaller than the input.
    static func smaller(_ input: Data) -> Data? {
        guard input.count > 1, let packed = compress(input), packed.count < input.count else { return nil }
        return packed
    }

    static func compress(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        var source = [UInt8](input)
        let bound = Int(deflateBound(&stream, uLong(source.count)))
        var output = [UInt8](repeating: 0, count: max(bound, 64))
        let status: Int32 = source.withUnsafeMutableBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                stream.next_in = src.baseAddress
                stream.avail_in = uInt(src.count)
                stream.next_out = dst.baseAddress
                stream.avail_out = uInt(dst.count)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { return nil }
        output.removeLast(Int(stream.avail_out))
        return Data(output)
    }

    static func decompress(_ input: Data, limit: Int = 64 * 1024) -> Data? {
        guard !input.isEmpty else { return Data() }
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var source = [UInt8](input)
        var output = [UInt8]()
        output.reserveCapacity(min(limit, max(input.count * 2, 64)))
        var status = Z_OK
        source.withUnsafeMutableBufferPointer { src in
            stream.next_in = src.baseAddress
            stream.avail_in = uInt(src.count)
            while status == Z_OK, output.count <= limit {
                let start = output.count
                let chunk = 256
                output.append(contentsOf: repeatElement(0, count: chunk))
                output.withUnsafeMutableBufferPointer { dst in
                    stream.next_out = dst.baseAddress?.advanced(by: start)
                    stream.avail_out = uInt(chunk)
                    status = inflate(&stream, Z_NO_FLUSH)
                }
                let made = chunk - Int(stream.avail_out)
                if made < chunk { output.removeLast(chunk - made) }
            }
        }
        guard status == Z_STREAM_END, output.count <= limit else { return nil }
        return Data(output)
    }
}

/// The bytes inside a sealed invite, before compression. Field order is fixed. A flag bit stands in for a long name.
enum InvitePlain {
    private static let region: UInt8 = 1 << 0
    private static let r2: UInt8 = 1 << 1
    private static let access16: UInt8 = 1 << 2
    private static let secret32: UInt8 = 1 << 3
    private static let library16: UInt8 = 1 << 4
    private static let owner32: UInt8 = 1 << 5
    private static let libraryULID: UInt8 = 1 << 6
    private static let libraryUUIDUpper: UInt8 = 1 << 7
    private static let r2Suffix = ".r2.cloudflarestorage.com"

    static func encode(_ payload: InvitePayload) throws -> Data {
        var flags: UInt8 = 0
        var body = Data()
        appendDouble(payload.exp, to: &body)
        try appendString(payload.email, to: &body)
        try appendString(payload.bucket, to: &body)
        try appendString(payload.libraryName, to: &body)
        try appendString(payload.adminName, to: &body)
        if let account = r2Account(payload.endpoint) {
            flags |= r2
            body.append(account)
        } else {
            try appendString(payload.endpoint, to: &body)
        }
        if let key = hexBytes(payload.accessKeyId, count: 16) {
            flags |= access16
            body.append(key)
        } else {
            try appendString(payload.accessKeyId, to: &body)
        }
        if let secret = hexBytes(payload.secretAccessKey, count: 32) {
            flags |= secret32
            body.append(secret)
        } else {
            try appendString(payload.secretAccessKey, to: &body)
        }
        if let packed = PackedID.pack(payload.libraryId) {
            flags |= library16
            if packed.kind == .ulid { flags |= libraryULID }
            if packed.kind == .uuidUpper { flags |= libraryUUIDUpper }
            body.append(packed.bytes)
        } else {
            try appendString(payload.libraryId, to: &body)
        }
        if let owner = Base64URL.decode(payload.ownerPublicKey), owner.count == 32 {
            flags |= owner32
            body.append(owner)
        } else {
            try appendString(payload.ownerPublicKey, to: &body)
        }
        let regionValue = payload.region.isEmpty ? "auto" : payload.region
        if regionValue != "auto" {
            flags |= region
            try appendString(regionValue, to: &body)
        }
        return Data([flags]) + body
    }

    static func decode(_ data: Data) throws -> InvitePayload {
        var cursor = data
        guard let flags = cursor.pop() else { throw RedeemError.malformed }
        let exp = try cursor.popDouble()
        let email = try cursor.popString()
        let bucket = try cursor.popString()
        let libraryName = try cursor.popString()
        let adminName = try cursor.popString()
        let endpoint: String
        if flags & r2 != 0 {
            endpoint = r2Endpoint(try cursor.pop(16))
        } else {
            endpoint = try cursor.popString()
        }
        let accessKeyId = flags & access16 != 0 ? hex(try cursor.pop(16)) : try cursor.popString()
        let secretAccessKey = flags & secret32 != 0 ? hex(try cursor.pop(32)) : try cursor.popString()
        let libraryId: String
        if flags & library16 != 0 {
            let bytes = try cursor.pop(16)
            if flags & libraryULID != 0 {
                libraryId = PackedID.ulid(bytes)
            } else {
                libraryId = PackedID.uuid(bytes, upper: flags & libraryUUIDUpper != 0)
            }
        } else {
            libraryId = try cursor.popString()
        }
        let ownerPublicKey: String
        if flags & owner32 != 0 {
            ownerPublicKey = Base64URL.encode(try cursor.pop(32))
        } else {
            ownerPublicKey = try cursor.popString()
        }
        let region = flags & region != 0 ? try cursor.popString() : "auto"
        guard cursor.isEmpty else { throw RedeemError.malformed }
        return InvitePayload(
            endpoint: endpoint, region: region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey,
            email: email, libraryId: libraryId, libraryName: libraryName, adminName: adminName, ownerPublicKey: ownerPublicKey, exp: exp
        )
    }

    private static func r2Account(_ endpoint: String) -> Data? {
        let prefix = "https://"
        guard endpoint.hasPrefix(prefix), endpoint.hasSuffix(r2Suffix) else { return nil }
        let host = endpoint.dropFirst(prefix.count).dropLast(r2Suffix.count)
        guard host.count == 32, host.allSatisfy(isLowerHex) else { return nil }
        return hexBytes(String(host), count: 16)
    }

    private static func r2Endpoint(_ account: Data) -> String {
        "https://\(hex(account)).r2.cloudflarestorage.com"
    }

    private static func isLowerHex(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return (ascii >= 48 && ascii <= 57) || (ascii >= 97 && ascii <= 102)
    }

    private static func hexBytes(_ text: String, count: Int) -> Data? {
        guard text.count == count * 2, text.allSatisfy(isLowerHex) else { return nil }
        var out = Data()
        out.reserveCapacity(count)
        var index = text.startIndex
        for _ in 0..<count {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendDouble(_ value: Double, to data: inout Data) {
        var bits = value.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private static func appendString(_ text: String, to data: inout Data) throws {
        let bytes = Data(text.utf8)
        guard bytes.count <= Int(UInt16.max) else { throw RedeemError.malformed }
        var count = UInt16(bytes.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}

enum PackedID {
    enum Kind { case ulid, uuidUpper, uuidLower }

    static func pack(_ text: String) -> (kind: Kind, bytes: Data)? {
        if let bytes = ulidBytes(text) { return (.ulid, bytes) }
        if let bytes = uuidBytes(text) {
            let upper = text.contains(where: { $0.isUppercase })
            return (upper ? .uuidUpper : .uuidLower, bytes)
        }
        return nil
    }

    static func ulid(_ bytes: Data) -> String { ulidString(bytes) }
    static func uuid(_ bytes: Data, upper: Bool) -> String { uuidString(bytes, upper: upper) }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static func ulidBytes(_ text: String) -> Data? {
        guard text.count == 26 else { return nil }
        var values: [Int] = []
        values.reserveCapacity(26)
        for character in text {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            values.append(alphabet.distance(from: alphabet.startIndex, to: index))
        }
        guard values[0] <= 7 else { return nil }
        var bits = ""
        for value in values {
            var chunk = ""
            var rest = value
            for _ in 0..<5 {
                chunk = ((rest & 1) == 1 ? "1" : "0") + chunk
                rest >>= 1
            }
            bits += chunk
        }
        return bytes(fromBits: String(bits.dropFirst(2)))
    }

    private static func ulidString(_ data: Data) -> String {
        guard data.count == 16 else { return "" }
        var bits = "00"
        for byte in data {
            var chunk = ""
            var rest = Int(byte)
            for _ in 0..<8 {
                chunk = ((rest & 1) == 1 ? "1" : "0") + chunk
                rest >>= 1
            }
            bits += chunk
        }
        var out = ""
        var index = bits.startIndex
        for _ in 0..<26 {
            var value = 0
            for _ in 0..<5 {
                value = (value << 1) | (bits[index] == "1" ? 1 : 0)
                index = bits.index(after: index)
            }
            out.append(alphabet[value])
        }
        return out
    }

    private static func uuidBytes(_ text: String) -> Data? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        let hex = parts.joined()
        guard hex.count == 32 else { return nil }
        var out = Data()
        var index = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    private static func uuidString(_ data: Data, upper: Bool) -> String {
        let hex = data.map { String(format: upper ? "%02X" : "%02x", $0) }.joined()
        let cuts = [8, 12, 16, 20]
        var out = ""
        var cursor = hex.startIndex
        var previous = 0
        for cut in cuts {
            let end = hex.index(cursor, offsetBy: cut - previous)
            out += hex[cursor..<end] + "-"
            cursor = end
            previous = cut
        }
        out += hex[cursor...]
        return out
    }

    private static func bytes(fromBits bits: String) -> Data? {
        guard bits.count == 128 else { return nil }
        var data = Data()
        var index = bits.startIndex
        for _ in 0..<16 {
            var byte = 0
            for _ in 0..<8 {
                byte = (byte << 1) | (bits[index] == "1" ? 1 : 0)
                index = bits.index(after: index)
            }
            data.append(UInt8(byte))
        }
        return data
    }
}

private extension Data {
    mutating func pop() -> UInt8? {
        guard !isEmpty else { return nil }
        return removeFirst()
    }

    mutating func pop(_ count: Int) throws -> Data {
        guard count >= 0, self.count >= count else { throw RedeemError.malformed }
        let slice = prefix(count)
        removeFirst(count)
        return Data(slice)
    }

    mutating func popDouble() throws -> Double {
        let raw = try pop(8)
        let bits = raw.withUnsafeBytes { UInt64(bigEndian: $0.load(as: UInt64.self)) }
        return Double(bitPattern: bits)
    }

    mutating func popString() throws -> String {
        let count = Int(try pop(2).withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) })
        let bytes = try pop(count)
        guard let text = String(data: bytes, encoding: .utf8) else { throw RedeemError.malformed }
        return text
    }
}
