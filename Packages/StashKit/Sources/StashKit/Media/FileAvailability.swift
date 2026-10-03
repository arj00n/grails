import Foundation

/// Is a file's content on this Mac, or just a placeholder that a sync client would have to download first?
/// Browsing must never touch placeholders (reading one forces a download), so the grid uses the shared thumbnail instead.
public enum FileAvailability: Sendable, Equatable {
    case local
    case cloudOnly

    /// `SF_DATALESS`: set by macOS File Provider (Google Drive, Dropbox, OneDrive) on not-yet-downloaded files.
    public static let datalessFlag: UInt32 = 0x4000_0000

    public static func isDataless(flags: UInt32) -> Bool { flags & datalessFlag != 0 }

    public static func of(_ url: URL) -> FileAvailability {
        var st = stat()
        if stat(url.path, &st) == 0, isDataless(flags: st.st_flags) { return .cloudOnly }
        if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
           v != .current, v != .downloaded { return .cloudOnly }
        return .local
    }

    /// Asks iCloud to fetch the file. (File Provider placeholders download simply by being read.)
    public static func requestDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
