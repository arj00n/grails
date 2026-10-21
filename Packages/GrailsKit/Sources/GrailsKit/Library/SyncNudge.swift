import Foundation

/// Which folder events should start another bucket poll. The sync manifest is rewritten at the end of a poll that actually changed the cursor. Watching that write — the file, its atomic temp, or the folder that holds it — and immediately polling again never leaves the loop idle.
public enum SyncNudge {
    public static func shouldNudge(paths: [String]) -> Bool {
        var sawRealFile = false
        for path in paths {
            if isSyncBookkeeping(path) { continue }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { continue }
            sawRealFile = true
        }
        if sawRealFile { return true }
        if paths.isEmpty { return false }
        // A folder event with no file beside it can be a new item whose file event has not arrived yet.
        return paths.allSatisfy { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    public static func isSyncManifest(_ path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent == ".grails-sync.json"
    }

    /// The manifest, or the temporary file an atomic write leaves beside it.
    static func isSyncBookkeeping(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name == ".grails-sync.json" || name.hasPrefix(".grails-sync.json")
    }
}
