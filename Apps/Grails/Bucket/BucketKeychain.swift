import Foundation
import GrailsSync
import Security

enum BucketKeychainError: Error {
    case status(OSStatus)
    /// The keychain could not be read. Callers must not mint or write secrets on top of that.
    case unavailable
}

/// Secrets for bucket sync. One keychain item holds every library. Nothing here is written to the library, logs, or the pasteboard.
enum BucketKeychain {
    static let service = "\(Bundle.main.bundleIdentifier ?? "xyz.arjoon.grails").bucket"
    private static let session = SecretSession()
    private static let gate = NSLock()
    nonisolated(unsafe) private static var loaded = false

    /// One keychain read for the process. Later loads, including a workspace switch, stay in memory.
    /// A demo or a scripted launch skips the read: SecItemCopyMatching can wait forever on a password panel.
    static func warm() {
        try? ensureLoaded()
    }

    static func save(account: String, data: Data) throws {
        try ensureLoaded()
        let previous = session.current()
        let next = session.update { SecretAccounts.write(account, data: data, into: &$0) }
        do {
            try writeBundle(next)
        } catch {
            session.store(previous ?? SecretBundle())
            throw error
        }
    }

    static func load(account: String) -> Data? {
        guard (try? ensureLoaded()) != nil else { return nil }
        guard let bundle = session.current() else { return nil }
        return SecretAccounts.value(for: account, in: bundle)
    }

    static func delete(account: String) {
        // A failed load must not write. The credentials stay until a later read succeeds.
        guard (try? ensureLoaded()) != nil, let previous = session.current() else { return }
        let next = session.update { SecretAccounts.clear(account, in: &$0) }
        do {
            try writeBundle(next)
        } catch {
            session.store(previous)
        }
    }

    private static func ensureLoaded() throws {
        gate.lock()
        defer { gate.unlock() }
        if loaded { return }
        let decision = KeychainPolicy.load(bundle: copyOne(account: SecretAccounts.bundle), listing: copyAll())
        switch decision {
        case .blocked:
            throw BucketKeychainError.unavailable
        case .ready(let bundle, let persist):
            session.store(bundle)
            if persist {
                try writeBundle(bundle)
                if case .items(let items) = copyAll() {
                    let legacy = SecretAccounts.absorb(items).legacy
                    for account in legacy { deleteAccount(account) }
                }
            }
            loaded = true
        }
    }

    /// Updates the existing item. Adds one only when it is not there. A failed update leaves the old item in place.
    private static func writeBundle(_ bundle: SecretBundle) throws {
        let data = try JSONEncoder().encode(bundle)
        let query = baseQuery(account: SecretAccounts.bundle)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch KeychainPolicy.store(updateStatus: status) {
        case .updated:
            return
        case .add:
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw BucketKeychainError.status(added) }
        case .failed(let code):
            throw BucketKeychainError.status(code)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func copyOne(account: String) -> KeychainOutcome {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(quiet(query) as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return .value(data) }
        if status == errSecItemNotFound { return .missing }
        return .failed(status)
    }

    /// A demo or a scripted launch must not sit on a keychain password panel.
    private static var suppressPrompt: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["GRAILS_LIBRARY"] != nil || env["GRAILS_SCREEN"] != nil || env["GRAILS_SNAPSHOT"] != nil { return true }
        return env.keys.contains { $0.hasPrefix("GRAILS_") && $0.hasSuffix("_DEMO") }
    }

    private static func quiet(_ query: [String: Any]) -> [String: Any] {
        guard suppressPrompt else { return query }
        var query = query
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }

    /// `kSecMatchLimitAll` together with `kSecReturnData` returns `errSecParam` on the file-based login keychain.
    /// Absorb would then see no items, write no `secrets` bundle, and leave the legacy accounts in place.
    /// Ask for attributes only, then read each account with `copyOne` (`kSecMatchLimitOne` + `kSecReturnData`).
    private static func copyAll() -> KeychainListing {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(quiet(query) as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let rows = item as? [[String: Any]] else { return .failed(status) }
        var out: [String: Data] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            switch copyOne(account: account) {
            case .value(let data):
                out[account] = data
            case .missing:
                continue
            case .failed(let code):
                return .failed(code)
            }
        }
        return out.isEmpty ? .missing : .items(out)
    }

    private static func deleteAccount(_ account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    static let deviceKeyAccount = SecretAccounts.device

    static func deviceKey() throws -> DeviceKey {
        try ensureLoaded()
        if let data = load(account: deviceKeyAccount), let key = try? DeviceKey(privateRaw: data) { return key }
        let key = DeviceKey()
        try save(account: deviceKeyAccount, data: key.privateRaw)
        return key
    }

    /// The key already on this Mac. Looking up a role must not mint a new one.
    static func existingDeviceKey() -> DeviceKey? {
        guard let data = load(account: deviceKeyAccount) else { return nil }
        return try? DeviceKey(privateRaw: data)
    }

    static func replaceDeviceKey(_ raw: Data) throws {
        let key = try DeviceKey(privateRaw: raw)
        try save(account: deviceKeyAccount, data: key.privateRaw)
    }
}

struct StoredAccess: Codable, Equatable, Sendable {
    var endpoint: URL
    var region: String
    var bucket: String
    var accessKeyId: String
    var secretAccessKey: String
    var email: String
}

extension StoredAccess: CustomStringConvertible {
    var description: String { "StoredAccess(bucket: \(bucket), email: \(email), secretAccessKey: <redacted>)" }
}

struct CloudflareLogin: Codable {
    var accountID: String
    var token: String
}

extension BucketKeychain {
    static func accessAccount(_ libraryID: String) -> String { SecretAccounts.access(libraryID) }
    static func retiredAccount(_ libraryID: String) -> String { SecretAccounts.retired(libraryID) }
    static func backupAccount(_ libraryID: String) -> String { SecretAccounts.backup(libraryID) }
    static let cloudflareAccount = SecretAccounts.cloudflare

    static func saveAccess(_ access: StoredAccess, libraryID: String) throws {
        try save(account: accessAccount(libraryID), data: JSONEncoder().encode(access))
    }

    static func loadAccess(libraryID: String) -> StoredAccess? {
        guard let data = load(account: accessAccount(libraryID)) else { return nil }
        return try? JSONDecoder().decode(StoredAccess.self, from: data)
    }

    static func saveCloudflare(_ login: CloudflareLogin) throws {
        try save(account: cloudflareAccount, data: JSONEncoder().encode(login))
    }

    static func loadCloudflare() -> CloudflareLogin? {
        guard let data = load(account: cloudflareAccount) else { return nil }
        return try? JSONDecoder().decode(CloudflareLogin.self, from: data)
    }
}
