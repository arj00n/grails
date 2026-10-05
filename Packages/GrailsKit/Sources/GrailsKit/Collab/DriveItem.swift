import Foundation

/// Drive for desktop records each file's and folder's Drive id in an extended attribute. With it Grails can open Drive's own page for
/// exactly that folder in the browser, where the person clicks Share. No sign-in and no Google API: it is a plain web address.
public enum DriveItemID {
    /// The attribute Drive for desktop writes (the `#S` is part of the name as macOS stores it), then the bare name as a fallback.
    public static let attributeNames = ["com.google.drivefs.item-id#S", "com.google.drivefs.item-id"]

    /// Reads one extended attribute; injectable so tests don't need a Drive.
    public typealias Reader = @Sendable (_ url: URL, _ name: String) -> Data?

    public static let systemReader: Reader = { url, name in
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read > 0 ? data.prefix(read) : nil
        }
    }

    /// The Drive id of `url`, or nil (not in Drive, Drive hasn't taken it yet, or the attribute isn't readable).
    public static func read(_ url: URL, reader: Reader = systemReader) -> String? {
        for name in attributeNames {
            guard let data = reader(url, name), var s = String(data: data, encoding: .utf8) else { continue }
            s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            if isValid(s) { return s }
        }
        return nil
    }

    /// Drive ids are 19–44 characters of letters, digits, `-` and `_` (Shared drive ids start `0A`). Anything else, such as a local
    /// placeholder Drive hasn't uploaded yet, is not a link target.
    public static func isValid(_ s: String) -> Bool {
        guard (10...80).contains(s.count), !s.lowercased().hasPrefix("local") else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Drive's own web pages. `authuser` picks the signed-in Google account in the browser, so a work folder doesn't open in a personal account.
public enum DriveWeb {
    static let base = "https://drive.google.com/drive"

    public static func folder(id: String, account: String?) -> URL { url("\(base)/folders/\(id)", account: account) }
    public static func sharedDrives(account: String?) -> URL { url("\(base)/shared-drives", account: account) }
    public static func myDrive(account: String?) -> URL { url("\(base)/my-drive", account: account) }
    public static func sharedWithMe(account: String?) -> URL { url("\(base)/shared-with-me", account: account) }
    public static let download = URL(string: "https://www.google.com/drive/download/")!

    /// The best page for a place: the folder itself when its id is known, otherwise the list it sits in.
    public static func page(for placement: Placement, folderID: String?) -> URL {
        if let folderID, DriveItemID.isValid(folderID) { return folder(id: folderID, account: placement.account) }
        switch placement.kind {
        case .sharedDrive, .driveTop: return sharedDrives(account: placement.account)
        case .sharedWithMe: return sharedWithMe(account: placement.account)
        default: return myDrive(account: placement.account)
        }
    }

    private static func url(_ s: String, account: String?) -> URL {
        var c = URLComponents(string: s)!
        if let account, !account.isEmpty { c.queryItems = [URLQueryItem(name: "authuser", value: account)] }
        return c.url!
    }
}

/// What the file system says about a library folder, gathered by the app (`FileFacts.read`) or made up by tests.
public struct FileFacts: Equatable, Sendable {
    /// Drive's id for the folder, once Drive has it.
    public var driveItemID: String?
    /// `library.json` is a placeholder: the library's files aren't on this Mac.
    public var manifestOnlineOnly = false
    /// From the system's ubiquitous-item keys, when the sync client reports them (nil = it didn't say).
    public var uploaded: Bool?
    public var uploading: Bool?
    public var uploadError: String?

    public init(driveItemID: String? = nil, manifestOnlineOnly: Bool = false, uploaded: Bool? = nil, uploading: Bool? = nil, uploadError: String? = nil) {
        self.driveItemID = driveItemID; self.manifestOnlineOnly = manifestOnlineOnly; self.uploaded = uploaded; self.uploading = uploading; self.uploadError = uploadError
    }

    /// Reads the folder's facts without downloading anything: an attribute, a `stat`, and resource values.
    public static func read(library url: URL, reader: DriveItemID.Reader = DriveItemID.systemReader) -> FileFacts {
        var f = FileFacts()
        f.driveItemID = DriveItemID.read(url, reader: reader)
        let manifest = url.appendingPathComponent("library.json")
        f.manifestOnlineOnly = FileAvailability.of(manifest) == .cloudOnly
        if let v = try? manifest.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]),
           v.isUbiquitousItem == true {
            f.uploaded = v.ubiquitousItemIsUploaded
            f.uploading = v.ubiquitousItemIsUploading
            f.uploadError = v.ubiquitousItemUploadingError?.localizedDescription
        }
        return f
    }
}
