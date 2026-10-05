import Foundation

/// Looks for a library by its id in every synced folder this Mac has, including the places `SyncedRoots.libraries` skips: Shared drives
/// a few levels down and folders shared with this account (`.shortcut-targets-by-id`).
public enum LibraryFinder {
    public static func find(id: String, accounts: [DriveAccount], otherRoots: [URL] = [], hint: LibraryHint? = nil,
                            budget: TimeInterval = 1.5, fileManager fm: FileManager = .default) -> URL? {
        let deadline = Date().addingTimeInterval(budget)
        var starts: [URL] = []
        let usable = accounts.filter { $0.state == .ready }
        let ready = usable.filter { $0.domain == hint?.domain } + usable.filter { $0.domain != hint?.domain }
        if let place = hint?.place, hint?.kind == .sharedDrive {
            starts += ready.flatMap { $0.sharedDrives.filter { $0.name == place }.map(\.url) }
        }
        for a in ready {
            starts += a.sharedDrives.map(\.url)
            if let my = a.myDrive { starts.append(my) }
            starts.append(a.root.appendingPathComponent(DriveFolderNames.shortcutTargets, isDirectory: true))
        }
        starts += otherRoots
        // breadth first, so a library next to a big, deep folder is found before the walk has spent its time inside that folder
        var seen = Set<String>()
        var queue: [(url: URL, depth: Int)] = starts.map { ($0, 1) }
        var next = 0
        while next < queue.count, Date() < deadline {
            let (dir, depth) = queue[next]
            next += 1
            guard seen.insert(dir.resolvingSymlinksInPath().path).inserted else { continue }
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") || $0 == DriveFolderNames.shortcutTargets }
            for name in names.sorted() {
                let url = dir.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                // fileExists follows symlinks, so My Drive shortcuts to shared folders are walked too
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if fm.fileExists(atPath: url.appendingPathComponent("library.json").path) {
                    if libraryID(at: url) == id { return url }
                    continue                                      // never look inside a library
                }
                if depth < 4 { queue.append((url, depth + 1)) }
            }
        }
        return nil
    }

    static func libraryID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("library.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["id"] as? String
    }
}

/// What this Mac has, for working out why an invite's library can't be found. Gathered by the app; made up in tests.
public struct JoinFacts: Sendable {
    public var driveAppInstalled: Bool
    public var accounts: [DriveAccount]
    public var otherServices: [CloudService]
    public var found: URL?

    public init(driveAppInstalled: Bool, accounts: [DriveAccount], otherServices: [CloudService] = [], found: URL? = nil) {
        self.driveAppInstalled = driveAppInstalled; self.accounts = accounts; self.otherServices = otherServices; self.found = found
    }
}

/// Something the teammate can do about it, as a button.
public enum JoinAction: String, Sendable, CaseIterable {
    case installDrive, openDriveApp, openPrivacySettings, openSharedWithMe, askForAccess, checkAgain, locate

    public var label: String {
        switch self {
        case .installDrive: "Get Google Drive"
        case .openDriveApp: "Open Google Drive"
        case .openPrivacySettings: "Open Settings"
        case .openSharedWithMe: "Open Shared with me"
        case .askForAccess: "Ask for access"
        case .checkAgain: "Check again"
        case .locate: "Locate folder…"
        }
    }
}

/// Why an invite's library isn't on this Mac, as best this Mac can tell. Grails can't see Drive's sharing; it can see what Drive for
/// desktop shows here, and the link says where the library lives.
public enum JoinDiagnosis: Equatable, Sendable {
    case found(URL)
    /// Drive for desktop isn't installed (or, for Dropbox and the rest, that app isn't).
    case noApp(CloudService)
    /// Drive for desktop is installed but no account is showing (not signed in, or Drive isn't running).
    case notSignedIn
    /// Accounts are there but macOS won't let Grails list them.
    case cannotRead
    /// The library is in a work Drive and this Mac is signed in to other accounts only.
    case wrongAccount(domain: String, signedIn: [String])
    /// Drive is fine; the library just isn't in it (not shared yet, no shortcut yet, or still syncing).
    case notShared(signedIn: [String])

    public static func diagnose(hint: LibraryHint?, facts: JoinFacts) -> JoinDiagnosis {
        if let url = facts.found { return .found(url) }
        let service = hint?.service ?? .googleDrive
        guard service == .googleDrive else {
            return facts.otherServices.contains(service) ? .notShared(signedIn: []) : .noApp(service)
        }
        guard !facts.accounts.isEmpty else { return facts.driveAppInstalled ? .notSignedIn : .noApp(.googleDrive) }
        let ready = facts.accounts.filter { $0.state == .ready }
        if ready.isEmpty {
            return facts.accounts.contains { $0.state == .unreadable } ? .cannotRead : .notSignedIn
        }
        if let domain = hint?.domain, hint?.isConsumerDomain == false, !ready.contains(where: { $0.domain == domain }) {
            return .wrongAccount(domain: domain, signedIn: ready.map(\.email))
        }
        let relevant = hint?.domain.flatMap { d in hint?.isConsumerDomain == false ? ready.filter { $0.domain == d } : nil } ?? ready
        return .notShared(signedIn: relevant.map(\.email))
    }

    /// The screen's words: a title, one line, the steps, then the main button and the others.
    public struct Copy: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var steps: [String]
        public var primary: JoinAction
        public var secondary: [JoinAction]
    }

    public func copy(library: String, hint: LibraryHint?) -> Copy {
        let account = hint?.domain.flatMap { DriveAccount.consumerDomains.contains($0) ? nil : "your \($0) account" } ?? "the account it was shared with"
        let more: [JoinAction] = [.checkAgain, .locate]
        switch self {
        case .found:
            return Copy(title: "Found", detail: "\(library) is on this Mac.", steps: [], primary: .checkAgain, secondary: [])
        case .noApp(let s) where s == .googleDrive:
            return Copy(title: "Google Drive isn't set up", detail: "\(library) lives in Google Drive. Grails reads it through Drive for desktop.",
                        steps: ["Install Google Drive for desktop", "Sign in with \(account)", "Come back here; Grails looks again by itself"],
                        primary: .installDrive, secondary: [.askForAccess] + more)
        case .noApp(let s):
            return Copy(title: "\(s.label) isn't set up", detail: "\(library) lives in \(s.label), which isn't on this Mac.",
                        steps: ["Install \(s.label) and sign in", "Accept the shared folder", "Come back here; Grails looks again by itself"],
                        primary: .askForAccess, secondary: more)
        case .notSignedIn:
            return Copy(title: "Google Drive isn't signed in", detail: "Drive for desktop is installed, but no account is showing.",
                        steps: ["Open Google Drive", "Sign in with \(account)", "Grails looks again by itself"],
                        primary: .openDriveApp, secondary: [.askForAccess] + more)
        case .cannotRead:
            return Copy(title: "Can't look inside Drive", detail: "macOS isn't letting Grails see Google Drive's folders.",
                        steps: ["Open System Settings ▸ Privacy & Security ▸ Files & Folders", "Allow Grails to open Google Drive", "Grails looks again by itself"],
                        primary: .openPrivacySettings, secondary: more)
        case .wrongAccount(let domain, let signedIn):
            return Copy(title: "Different Google account", detail: "\(library) is in a \(domain) Drive. This Mac has \(Self.list(signedIn)).",
                        steps: ["Open Google Drive ▸ Settings ▸ Add another account", "Sign in with your \(domain) account", "Grails looks again by itself"],
                        primary: .openDriveApp, secondary: [.askForAccess] + more)
        case .notShared(let signedIn):
            let inDrive = signedIn.isEmpty ? "" : " (\(Self.list(signedIn)))"
            switch hint?.kind {
            case .sharedDrive?:
                let drive = hint?.place.map { "the Shared drive “\($0)”" } ?? "a Shared drive"
                return Copy(title: "Not shared with you yet", detail: "\(library) is in \(drive), which isn't in your Drive\(inDrive).",
                            steps: ["Ask the owner to add you to \(hint?.place.map { "“\($0)”" } ?? "it")", "Drive shows it within a few minutes", "Grails opens it by itself"],
                            primary: .askForAccess, secondary: more)
            case .myDrive?:
                return Copy(title: "Add it to your Drive", detail: "\(library) is a folder shared from someone's Drive. Drive for desktop only shows it once you add a shortcut.",
                            steps: ["Open Shared with me on drive.google.com", "Right-click “\(library)” ▸ Organize ▸ Add shortcut ▸ My Drive", "Not there? Ask for access"],
                            primary: .openSharedWithMe, secondary: [.askForAccess] + more)
            case nil:
                return Copy(title: "Can't find \(library)", detail: "It isn't in any folder your sync apps show here\(inDrive).",
                            steps: ["Ask the owner to share it with you", "If it's shared already, let Drive finish syncing", "Or locate the folder yourself"],
                            primary: .askForAccess, secondary: more)
            default:
                let s = hint?.service.label ?? "your sync app"
                return Copy(title: "Not shared with you yet", detail: "\(library) is a shared folder in \(s) that isn't on this Mac yet.",
                            steps: ["Accept the shared folder in \(s)", "Let it sync", "Grails opens it by itself"],
                            primary: .askForAccess, secondary: more)
            }
        }
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return "no account"
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
