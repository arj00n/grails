import Foundation

public struct LibrarySecrets: Codable, Equatable, Sendable {
    public var access: Data?
    public var retired: Data?
    public var backup: Data?

    public init(access: Data? = nil, retired: Data? = nil, backup: Data? = nil) {
        self.access = access
        self.retired = retired
        self.backup = backup
    }
}

/// Every Grails secret for this Mac, in one keychain item. Libraries are keyed by id.
public struct SecretBundle: Codable, Equatable, Sendable {
    public var devicePrivateKey: Data?
    public var cloudflare: Data?
    public var libraries: [String: LibrarySecrets]

    public init(devicePrivateKey: Data? = nil, cloudflare: Data? = nil, libraries: [String: LibrarySecrets] = [:]) {
        self.devicePrivateKey = devicePrivateKey
        self.cloudflare = cloudflare
        self.libraries = libraries
    }
}

public enum SecretAccounts {
    public static let bundle = "secrets"
    public static let device = "device-private-key"
    public static let cloudflare = "cloudflare-api"

    public static func access(_ libraryID: String) -> String { "s3.\(libraryID)" }
    public static func retired(_ libraryID: String) -> String { "s3-retired.\(libraryID)" }
    public static func backup(_ libraryID: String) -> String { "backup.\(libraryID)" }

    /// Folds the old one-account-per-secret items into the bundle. The bundle's own values win.
    public static func absorb(_ items: [String: Data]) -> (bundle: SecretBundle, legacy: [String]) {
        let bundleAccount = bundle
        var merged = SecretBundle()
        if let data = items[bundleAccount], let decoded = try? JSONDecoder().decode(SecretBundle.self, from: data) {
            merged = decoded
        }
        var legacy: [String] = []
        for (account, data) in items where account != bundleAccount {
            legacy.append(account)
            if account == device {
                if merged.devicePrivateKey == nil { merged.devicePrivateKey = data }
                continue
            }
            if account == cloudflare {
                if merged.cloudflare == nil { merged.cloudflare = data }
                continue
            }
            if let id = libraryID(in: account, prefix: "s3-retired.") {
                var row = merged.libraries[id] ?? LibrarySecrets()
                if row.retired == nil { row.retired = data }
                merged.libraries[id] = row
                continue
            }
            if let id = libraryID(in: account, prefix: "backup.") {
                var row = merged.libraries[id] ?? LibrarySecrets()
                if row.backup == nil { row.backup = data }
                merged.libraries[id] = row
                continue
            }
            if let id = libraryID(in: account, prefix: "s3.") {
                var row = merged.libraries[id] ?? LibrarySecrets()
                if row.access == nil { row.access = data }
                merged.libraries[id] = row
            }
        }
        return (merged, legacy.sorted())
    }

    public static func value(for account: String, in bundle: SecretBundle) -> Data? {
        if account == device { return bundle.devicePrivateKey }
        if account == cloudflare { return bundle.cloudflare }
        if let id = libraryID(in: account, prefix: "s3-retired.") { return bundle.libraries[id]?.retired }
        if let id = libraryID(in: account, prefix: "backup.") { return bundle.libraries[id]?.backup }
        if let id = libraryID(in: account, prefix: "s3.") { return bundle.libraries[id]?.access }
        return nil
    }

    public static func write(_ account: String, data: Data, into bundle: inout SecretBundle) {
        if account == device { bundle.devicePrivateKey = data; return }
        if account == cloudflare { bundle.cloudflare = data; return }
        if let id = libraryID(in: account, prefix: "s3-retired.") {
            var row = bundle.libraries[id] ?? LibrarySecrets()
            row.retired = data
            bundle.libraries[id] = row
            return
        }
        if let id = libraryID(in: account, prefix: "backup.") {
            var row = bundle.libraries[id] ?? LibrarySecrets()
            row.backup = data
            bundle.libraries[id] = row
            return
        }
        if let id = libraryID(in: account, prefix: "s3.") {
            var row = bundle.libraries[id] ?? LibrarySecrets()
            row.access = data
            bundle.libraries[id] = row
        }
    }

    public static func clear(_ account: String, in bundle: inout SecretBundle) {
        if account == device { bundle.devicePrivateKey = nil; return }
        if account == cloudflare { bundle.cloudflare = nil; return }
        if let id = libraryID(in: account, prefix: "s3-retired.") { bundle.libraries[id]?.retired = nil; return }
        if let id = libraryID(in: account, prefix: "backup.") { bundle.libraries[id]?.backup = nil; return }
        if let id = libraryID(in: account, prefix: "s3.") { bundle.libraries[id]?.access = nil }
    }

    private static func libraryID(in account: String, prefix: String) -> String? {
        guard account.hasPrefix(prefix) else { return nil }
        let id = String(account.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// The one in-memory copy of the secret bundle for this process. Keychain is not touched here.
public final class SecretSession: @unchecked Sendable {
    private let lock = NSLock()
    private var bundle: SecretBundle?

    public init() {}

    public func current() -> SecretBundle? {
        lock.lock()
        defer { lock.unlock() }
        return bundle
    }

    public func store(_ bundle: SecretBundle) {
        lock.lock()
        self.bundle = bundle
        lock.unlock()
    }

    public func update(_ body: (inout SecretBundle) -> Void) -> SecretBundle {
        lock.lock()
        var next = bundle ?? SecretBundle()
        body(&next)
        bundle = next
        lock.unlock()
        return next
    }
}

public enum KeychainPromptGate {
    public static let defaultsKey = "keychainPromptToken"

    public static func token(version: String, build: String) -> String { "\(version) (\(build))" }

    /// True the first launch after an install or update. The stored token is the version and the build.
    public static func needsHeadsUp(stored: String?, version: String, build: String) -> Bool {
        stored != token(version: version, build: build)
    }
}
