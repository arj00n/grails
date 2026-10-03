import Foundation

/// Every file Stash writes into a library goes through here: write to a temp sibling, then rename.
/// A sync client or a crash can never observe a half-written JSON file.
public enum AtomicFile {
    public static let tempMarker = ".tmp-"

    public static func isTemp(_ name: String) -> Bool { name.contains(tempMarker) }

    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(url.lastPathComponent + tempMarker + UUID().uuidString)
        try data.write(to: tmp)
        if Darwin.rename(tmp.path, url.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try write(StashJSON.encode(value), to: url)
    }
}
