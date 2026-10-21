import Foundation
import XCTest
import GrailsSync
#if os(macOS)
import Security
#endif

/// Secrets for a test. The box is memory. On a Mac, `reset` also deletes the login-keychain service `xyz.arjoon.grails.tests.<UUID>` so a test that mirrored the box into the keychain cannot leave it behind.
final class KeychainTestBox {
    private var items: [String: Data] = [:]
    let loginService = "xyz.arjoon.grails.tests.\(UUID().uuidString)"

    func write(account: String, data: Data) { items[account] = data }

    func read(account: String) -> Data? { items[account] }

    func listing() -> [String: Data] { items }

    func reset() {
        items = [:]
        #if os(macOS)
        // SecItemCopyMatching on the login keychain can sit on a password prompt forever. The box itself is memory.
        // Set GRAILS_KEYCHAIN_TESTS=1 when a test has mirrored a secret into the login keychain and it must be removed.
        guard ProcessInfo.processInfo.environment["GRAILS_KEYCHAIN_TESTS"] != nil else { return }
        KeychainTestLogin.delete(service: loginService)
        #endif
    }

    deinit { reset() }
}

final class KeychainBoxTests: XCTestCase {
    func testTheBoxDropsItsItems() {
        let box = KeychainTestBox()
        box.write(account: SecretAccounts.access("lib-a"), data: Data("access".utf8))
        box.write(account: SecretAccounts.device, data: Data("device".utf8))
        let absorbed = SecretAccounts.absorb(box.listing())
        XCTAssertEqual(absorbed.bundle.libraries["lib-a"]?.access, Data("access".utf8))
        XCTAssertEqual(absorbed.bundle.devicePrivateKey, Data("device".utf8))
        box.reset()
        XCTAssertNil(box.read(account: SecretAccounts.device))
        XCTAssertTrue(box.listing().isEmpty)
    }
}

#if os(macOS)
enum KeychainTestLogin {
    /// Attributes only, then delete each account. `kSecMatchLimitAll` with `kSecReturnData` is `errSecParam` on the file-based login keychain.
    static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let rows = item as? [[String: Any]] else {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ] as CFDictionary)
            return
        }
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary)
        }
    }
}
#endif
