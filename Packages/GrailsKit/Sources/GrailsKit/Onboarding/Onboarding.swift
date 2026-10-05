import Foundation

/// How a handle is written: lowercase letters, digits and `._-`, at most 32 characters. It is the name on everything you add.
public enum Handle {
    public static func normalize(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleaned = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil).map { allowed.contains($0) ? $0 : (($0 == " ") ? "-" : nil) }.compactMap { $0 }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return String(s.prefix(32))
    }
}

/// A synced folder on this Mac (Google Drive, Dropbox, OneDrive, Box, iCloud Drive) where a library can live.
public struct SyncedRoot: Equatable, Sendable, Identifiable {
    public var name: String
    public var url: URL
    public var id: String { url.path }
}

/// A Grails library already sitting in a synced folder: what a second Mac finds.
public struct FoundLibrary: Equatable, Sendable, Identifiable {
    public var name: String
    public var url: URL
    public var id: String { url.path }
}

public enum SyncedRoots {
    /// At most three, found in `~/Library/CloudStorage` and iCloud Drive. `home` is injectable for tests.
    public static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager fm: FileManager = .default) -> [SyncedRoot] {
        var out: [SyncedRoot] = []
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        for url in ((try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            out.append(SyncedRoot(name: displayName(url.lastPathComponent), url: url))
        }
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fm.fileExists(atPath: icloud.path) { out.append(SyncedRoot(name: "iCloud Drive", url: icloud)) }
        return Array(out.prefix(3))
    }

    /// "GoogleDrive-ana@studio.com" → "Google Drive", "Dropbox" → "Dropbox".
    static func displayName(_ folder: String) -> String {
        let service = folder.split(separator: "-").first.map(String.init) ?? folder
        switch service {
        case "GoogleDrive": return "Google Drive"
        case "OneDrive": return "OneDrive"
        default: return service
        }
    }

    /// Libraries (folders holding a `library.json`) up to three levels down, within a time box so a huge drive can't stall the screen.
    public static func libraries(in roots: [SyncedRoot], fileManager fm: FileManager = .default, budget: TimeInterval = 0.3) -> [FoundLibrary] {
        let deadline = Date().addingTimeInterval(budget)
        var found: [FoundLibrary] = []
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 3, Date() < deadline else { return }
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let manifest = url.appendingPathComponent("library.json")
                if fm.fileExists(atPath: manifest.path) {
                    let name = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])?["name"] as? String
                    found.append(FoundLibrary(name: name ?? url.deletingPathExtension().lastPathComponent, url: url))
                } else if !url.lastPathComponent.hasPrefix(".") {
                    walk(url, depth: depth + 1)
                }
            }
        }
        for r in roots { walk(r.url, depth: 1) }
        return Array(found.prefix(3))
    }
}

/// Where first-run onboarding is, kept so quitting halfway picks up again.
public struct OnboardingState: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable { case hello, library, importing, arriving }
    public var step: Step = .hello
    public var libraryPath: String?
    public var handle: String = ""
    public var done = false
    public init() {}

    public static func load(_ defaults: UserDefaults = .standard) -> OnboardingState {
        defaults.data(forKey: "onboarding.v1").flatMap { try? JSONDecoder().decode(OnboardingState.self, from: $0) } ?? OnboardingState()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "onboarding.v1") }
    }
}
