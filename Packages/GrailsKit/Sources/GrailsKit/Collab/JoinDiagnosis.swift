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

    /// The folder the open panel returns is often the one *around* the library: a `.grails` package looks like a file, so Open confirms the folder you are looking at.
    /// The package itself, the library named `name`, or the only library in that folder.
    public static func picked(_ chosen: URL, named name: String? = nil, fileManager fm: FileManager = .default) -> URL? {
        if libraryID(at: chosen) != nil { return chosen }
        let kids = (try? fm.contentsOfDirectory(at: chosen, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let libs = kids.filter { url in
            let ext = url.pathExtension.lowercased()
            return (ext == "grails" || ext == "stash") && libraryID(at: url) != nil
        }
        if let name {
            let want = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let hit = libs.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == want }) { return hit }
        }
        return libs.count == 1 ? libs[0] : nil
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

    /// One row of the join checklist. `done` is already true on this Mac; `current` is the next thing; `later` is what follows.
    public struct Step: Equatable, Sendable {
        public enum Mark: Equatable, Sendable { case done, current, later }
        public var text: String
        public var mark: Mark
    }

    /// The screen's words: a title and the checklist, then the main button and the others.
    public struct Copy: Equatable, Sendable {
        public var title: String
        public var steps: [Step]
        public var primary: JoinAction
        public var secondary: [JoinAction]
    }

    public func copy(library: String, hint: LibraryHint?) -> Copy {
        let account = Self.accountPhrase(hint)
        let more: [JoinAction] = [.checkAgain, .locate]
        switch self {
        case .found:
            return Copy(title: "Found", steps: [], primary: .checkAgain, secondary: [])
        case .noApp(let s) where s == .googleDrive:
            return Self.drive(library: library, hint: hint, signIn: "Sign in with \(account)", at: 0,
                               title: "Google Drive isn't set up", extra: [.askForAccess])
        case .noApp(let s):
            return Copy(title: "\(s.label) isn't set up",
                        steps: Self.marked(["Install \(s.label) and sign in", "Accept the shared folder", "Grails opens it"], at: 0),
                        primary: .askForAccess, secondary: more)
        case .notSignedIn:
            return Self.drive(library: library, hint: hint, signIn: "Sign in with \(account)", at: 1,
                               title: "Google Drive isn't signed in", extra: [.askForAccess])
        case .cannotRead:
            return Copy(title: "Can't look inside Drive",
                        steps: Self.marked(["Install Google Drive", "Allow Grails in Files and Folders", "Grails looks again"], at: 1),
                        primary: .openPrivacySettings, secondary: more)
        case .wrongAccount(let domain, _):
            return Self.drive(library: library, hint: hint, signIn: "Add your \(domain) account", at: 1,
                               title: "Different Google account", extra: [.askForAccess])
        case .notShared(let signedIn):
            switch hint?.kind {
            case .sharedDrive?, .myDrive?, nil:
                return Self.drive(library: library, hint: hint, signIn: "Sign in with \(account)", at: 2,
                                   title: Self.sharedTitle(library: library, hint: hint),
                                   extra: hint?.kind == .myDrive ? [.askForAccess] : [], signedIn: signedIn)
            default:
                let s = hint?.service.label ?? "your sync app"
                return Copy(title: "Not shared with you yet",
                            steps: Self.marked(["Install \(s) and sign in", "Accept the shared folder", "Grails opens it"], at: 1),
                            primary: .askForAccess, secondary: more)
            }
        }
    }

    /// Google Drive, in order. `at` is how far this Mac has got, from the diagnosis: 0 install, 1 the right account, 2 the library itself.
    private static func drive(library: String, hint: LibraryHint?, signIn: String, at current: Int, title: String, extra: [JoinAction], signedIn: [String] = []) -> Copy {
        let sign = (current > 1 && !signedIn.isEmpty) ? "Signed in as \(list(signedIn))" : signIn
        let primary = driveAction(at: current, hint: hint)
        var secondary = extra + [.checkAgain, .locate]
        secondary.removeAll { $0 == primary }
        return Copy(title: title, steps: marked(["Install Google Drive", sign, accessLine(library: library, hint: hint), "Grails opens it"], at: current),
                    primary: primary, secondary: secondary)
    }

    private static func driveAction(at index: Int, hint: LibraryHint?) -> JoinAction {
        switch index {
        case 0: .installDrive
        case 1: .openDriveApp
        default: hint?.kind == .myDrive ? .openSharedWithMe : .askForAccess
        }
    }

    private static func marked(_ lines: [String], at current: Int) -> [Step] {
        lines.enumerated().map { i, text in Step(text: text, mark: i < current ? .done : (i == current ? .current : .later)) }
    }

    private static func accountPhrase(_ hint: LibraryHint?) -> String {
        hint?.domain.flatMap { DriveAccount.consumerDomains.contains($0) ? nil : "your \($0) account" } ?? "the account it was shared with"
    }

    private static func accessLine(library: String, hint: LibraryHint?) -> String {
        switch hint?.kind {
        case .sharedDrive?: "Ask to be added to \(hint?.place.map { "“\($0)”" } ?? "the Shared drive")"
        case .myDrive?: "Add a shortcut to My Drive"
        case nil: "Ask the owner to share \(library)"
        default: "Accept the shared folder"
        }
    }

    private static func sharedTitle(library: String, hint: LibraryHint?) -> String {
        switch hint?.kind {
        case .myDrive?: "Add it to your Drive"
        case nil: "Can't find \(library)"
        default: "Not shared with you yet"
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
