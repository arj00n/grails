import Foundation

/// Which sync client a folder belongs to.
public enum CloudService: String, Codable, Sendable, CaseIterable {
    case googleDrive, dropbox, oneDrive, box, iCloud

    public var label: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .dropbox: "Dropbox"
        case .oneDrive: "OneDrive"
        case .box: "Box"
        case .iCloud: "iCloud Drive"
        }
    }

    /// `~/Library/CloudStorage/<folder>` → service. "GoogleDrive-ana@studio.com", "Dropbox", "OneDrive-Studio", "Box-Box".
    public static func of(cloudStorageFolder name: String) -> CloudService? {
        let service = name.split(separator: "-", maxSplits: 1).first.map(String.init) ?? name
        switch service {
        case "GoogleDrive": return .googleDrive
        case "Dropbox": return .dropbox
        case "OneDrive": return .oneDrive
        case "Box": return .box
        default: return nil
        }
    }
}

/// A Google Shared drive as Drive for desktop shows it: `Shared drives/<name>`.
public struct SharedDrive: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var url: URL
    public var id: String { url.path }
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

/// One Google account signed in to Drive for desktop: `~/Library/CloudStorage/GoogleDrive-<email>/`.
public struct DriveAccount: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        /// Its folders are listed.
        case ready
        /// The folder is there but empty: Drive isn't running, or this account was signed out.
        case empty
        /// macOS refused to list it (Privacy & Security), so nothing inside can be seen.
        case unreadable
    }

    public var email: String
    public var root: URL
    public var state: State
    public var myDrive: URL?
    public var sharedDrivesFolder: URL?
    public var sharedDrives: [SharedDrive]
    public var id: String { email }

    public init(email: String, root: URL, state: State, myDrive: URL? = nil, sharedDrivesFolder: URL? = nil, sharedDrives: [SharedDrive] = []) {
        self.email = email; self.root = root; self.state = state; self.myDrive = myDrive; self.sharedDrivesFolder = sharedDrivesFolder; self.sharedDrives = sharedDrives
    }

    public var domain: String { email.split(separator: "@").last.map { $0.lowercased() } ?? "" }
    /// A consumer account (gmail.com). A guess from the address: a Google account made on any other address looks like work too.
    public var isPersonal: Bool { DriveAccount.consumerDomains.contains(domain) }
    /// Shared drives need Google Workspace; consumer accounts never have them.
    public var canHaveSharedDrives: Bool { !isPersonal }

    public static let consumerDomains: Set<String> = ["gmail.com", "googlemail.com"]
}

/// What Drive for desktop calls its top folders. It localises them; these are the ones known here (English first). Anything else is
/// left alone, so an unknown language means "My Drive" / "Shared drives" aren't recognised, never a wrong answer.
public enum DriveFolderNames {
    public static let myDrive = ["My Drive", "Meine Ablage", "Mi unidad", "Mon Drive", "Il mio Drive", "Minha unidade", "Mijn Drive", "マイドライブ"]
    public static let sharedDrives = ["Shared drives", "Geteilte Ablagen", "Unidades compartidas", "Drives partagés", "Drive condivisi",
                                      "Drives compartilhados", "Gedeelde drives", "共有ドライブ"]
    public static let otherComputers = ["Other computers", "Andere Computer", "Otros ordenadores", "Autres ordinateurs", "Altri computer", "Outros computadores"]
    /// Where Drive for desktop keeps folders other people shared, which appear in My Drive as shortcuts.
    public static let shortcutTargets = ".shortcut-targets-by-id"
}

/// Reads `~/Library/CloudStorage` for Google accounts and other sync clients. `home` is injectable so tests use a fake tree.
public enum CloudPlaces {
    public static func storage(home: URL) -> URL { home.appendingPathComponent("Library/CloudStorage", isDirectory: true) }

    /// Every Google account Drive for desktop has a folder for, work accounts first.
    public static func driveAccounts(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager fm: FileManager = .default) -> [DriveAccount] {
        let storage = storage(home: home)
        let names = ((try? fm.contentsOfDirectory(atPath: storage.path)) ?? []).filter { $0.hasPrefix("GoogleDrive-") }.sorted()
        let accounts = names.map { account(at: storage.appendingPathComponent($0, isDirectory: true), fileManager: fm) }
        return accounts.sorted { ($0.isPersonal ? 1 : 0, $0.email) < ($1.isPersonal ? 1 : 0, $1.email) }
    }

    static func account(at root: URL, fileManager fm: FileManager) -> DriveAccount {
        let email = String(root.lastPathComponent.dropFirst("GoogleDrive-".count))
        guard let top = try? fm.contentsOfDirectory(atPath: root.path) else { return DriveAccount(email: email, root: root, state: .unreadable) }
        let visible = top.filter { !$0.hasPrefix(".") }
        guard !visible.isEmpty else { return DriveAccount(email: email, root: root, state: .empty) }
        let my = visible.first { DriveFolderNames.myDrive.contains($0) }.map { root.appendingPathComponent($0, isDirectory: true) }
        let sharedFolder = visible.first { DriveFolderNames.sharedDrives.contains($0) }.map { root.appendingPathComponent($0, isDirectory: true) }
        var drives: [SharedDrive] = []
        if let sharedFolder {
            drives = ((try? fm.contentsOfDirectory(atPath: sharedFolder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { SharedDrive(name: $0, url: sharedFolder.appendingPathComponent($0, isDirectory: true)) }
        }
        return DriveAccount(email: email, root: root, state: .ready, myDrive: my, sharedDrivesFolder: sharedFolder, sharedDrives: drives)
    }

    /// Other sync clients (Dropbox, OneDrive, Box, iCloud Drive): every one, unlike `SyncedRoots.detect`, which stops at three.
    public static func otherRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager fm: FileManager = .default) -> [(service: CloudService, root: SyncedRoot)] {
        var out: [(CloudService, SyncedRoot)] = []
        let storage = storage(home: home)
        for name in ((try? fm.contentsOfDirectory(atPath: storage.path)) ?? []).sorted() {
            guard let s = CloudService.of(cloudStorageFolder: name), s != .googleDrive else { continue }
            out.append((s, SyncedRoot(name: s.label, url: storage.appendingPathComponent(name, isDirectory: true))))
        }
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fm.fileExists(atPath: icloud.path) { out.append((.iCloud, SyncedRoot(name: "iCloud Drive", url: icloud))) }
        return out
    }

    /// Libraries already inside one folder (a Shared drive, My Drive), up to three levels down, within `budget` seconds.
    public static func libraries(in folder: URL, budget: TimeInterval = 0.15, fileManager fm: FileManager = .default) -> [FoundLibrary] {
        SyncedRoots.libraries(in: [SyncedRoot(name: "", url: folder)], fileManager: fm, budget: budget)
    }

    /// The account to suggest: a work account with Shared drives, then any work account, then a personal one.
    public static func preferred(_ accounts: [DriveAccount]) -> DriveAccount? {
        let usable = accounts.filter { $0.state == .ready }
        return usable.first { !$0.isPersonal && !$0.sharedDrives.isEmpty } ?? usable.first { !$0.isPersonal } ?? usable.first
    }
}

/// Where a library folder sits, worked out from its path alone.
public struct Placement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Inside a Google Shared drive: everyone the drive has as a member gets it.
        case sharedDrive(String)
        /// In someone's My Drive: only people the folder is shared with get it, and they have to add it to their own Drive.
        case myDrive
        /// A folder someone shared with this account (Drive keeps those apart, under `.shortcut-targets-by-id`).
        case sharedWithMe
        /// Drive's backup of a computer: not a place to work together.
        case otherComputers
        /// Drive account root or the `Shared drives` folder itself, where nothing can be made.
        case driveTop
        /// Dropbox, OneDrive, Box or iCloud Drive.
        case cloud(CloudService)
        /// Nowhere a sync client looks.
        case local
    }

    public var kind: Kind
    /// The Google account, for anything in Drive.
    public var account: String?
    /// Path below the service's root, e.g. `Shared drives/Design/Team Inspo.grails`.
    public var relativePath: String?
    public var inTrash: Bool

    public init(kind: Kind, account: String? = nil, relativePath: String? = nil, inTrash: Bool = false) {
        self.kind = kind; self.account = account; self.relativePath = relativePath; self.inTrash = inTrash
    }

    public var service: CloudService? {
        switch kind {
        case .sharedDrive, .myDrive, .sharedWithMe, .otherComputers, .driveTop: .googleDrive
        case .cloud(let s): s
        case .local: nil
        }
    }

    public var isSynced: Bool { kind != .local }

    /// "Shared drive Design", "My Drive", "Dropbox", "This Mac only".
    public var label: String {
        switch kind {
        case .sharedDrive(let d): "Shared drive \(d)"
        case .myDrive: "My Drive"
        case .sharedWithMe: "Shared with you"
        case .otherComputers: "Other computers"
        case .driveTop: "Google Drive"
        case .cloud(let s): s.label
        case .local: "This Mac only"
        }
    }

    /// Classifies `url` (a library or a folder to put one in). Only the path is read, so this never touches the network or a placeholder.
    public static func of(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Placement {
        let path = norm(url)
        let parts = path.split(separator: "/").map(String.init)
        let trash = parts.contains(".Trash") || parts.contains(".Trashes")
        let storage = norm(CloudPlaces.storage(home: home)) + "/"
        if path.hasPrefix(storage) {
            let rest = path.dropFirst(storage.count).split(separator: "/").map(String.init)
            guard let top = rest.first, let service = CloudService.of(cloudStorageFolder: top) else { return Placement(kind: .local, inTrash: trash) }
            let inner = Array(rest.dropFirst())
            let relative = inner.isEmpty ? nil : inner.joined(separator: "/")
            guard service == .googleDrive else { return Placement(kind: .cloud(service), relativePath: relative, inTrash: trash) }
            let account = String(top.dropFirst("GoogleDrive-".count))
            guard let first = inner.first else { return Placement(kind: .driveTop, account: account, inTrash: trash) }
            let kind: Kind
            if DriveFolderNames.sharedDrives.contains(first) { kind = inner.count >= 2 ? .sharedDrive(inner[1]) : .driveTop }
            else if DriveFolderNames.myDrive.contains(first) { kind = .myDrive }
            else if DriveFolderNames.otherComputers.contains(first) { kind = .otherComputers }
            else if first == DriveFolderNames.shortcutTargets { kind = .sharedWithMe }
            else { kind = .myDrive }
            return Placement(kind: kind, account: account, relativePath: relative, inTrash: trash)
        }
        let icloud = norm(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")) + "/"
        if path.hasPrefix(icloud) {
            return Placement(kind: .cloud(.iCloud), relativePath: String(path.dropFirst(icloud.count)), inTrash: trash)
        }
        // Drive for desktop in Mirror mode keeps My Drive in an ordinary folder, by default ~/My Drive or ~/Google Drive/My Drive.
        for mirror in ["My Drive", "Google Drive/My Drive", "Google Drive"] {
            let m = norm(home.appendingPathComponent(mirror)) + "/"
            if path.hasPrefix(m) { return Placement(kind: .myDrive, relativePath: "My Drive/" + path.dropFirst(m.count), inTrash: trash) }
        }
        let dropbox = norm(home.appendingPathComponent("Dropbox")) + "/"
        if path.hasPrefix(dropbox) { return Placement(kind: .cloud(.dropbox), relativePath: String(path.dropFirst(dropbox.count)), inTrash: trash) }
        return Placement(kind: .local, inTrash: trash)
    }

    /// The path without `.` / `..` and with `/private/tmp` and `/private/var` spelled one way. (`standardizedFileURL` drops `/private`
    /// only for paths that exist, which made a library and the folder it was about to go in disagree.)
    static func norm(_ url: URL) -> String {
        var p = url.absoluteURL.standardized.path
        for prefix in ["/private/tmp", "/private/var", "/private/etc"] where p == prefix || p.hasPrefix(prefix + "/") { p.removeFirst("/private".count) }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
