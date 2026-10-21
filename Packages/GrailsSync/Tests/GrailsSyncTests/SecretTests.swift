import Foundation
import XCTest
import GrailsSync

final class SecretTests: XCTestCase {
    func testLegacyAccountsFoldIntoOneBundle() throws {
        let items: [String: Data] = [
            SecretAccounts.device: Data("device".utf8),
            SecretAccounts.cloudflare: Data("token".utf8),
            SecretAccounts.access("lib-a"): Data("access-a".utf8),
            SecretAccounts.access("lib-b"): Data("access-b".utf8),
            SecretAccounts.retired("lib-a"): Data("retired-a".utf8),
            SecretAccounts.backup("lib-b"): Data("backup-b".utf8),
        ]
        let absorbed = SecretAccounts.absorb(items)
        XCTAssertEqual(absorbed.legacy, items.keys.sorted())
        XCTAssertEqual(absorbed.bundle.devicePrivateKey, Data("device".utf8))
        XCTAssertEqual(absorbed.bundle.cloudflare, Data("token".utf8))
        XCTAssertEqual(absorbed.bundle.libraries["lib-a"]?.access, Data("access-a".utf8))
        XCTAssertEqual(absorbed.bundle.libraries["lib-a"]?.retired, Data("retired-a".utf8))
        XCTAssertEqual(absorbed.bundle.libraries["lib-b"]?.access, Data("access-b".utf8))
        XCTAssertEqual(absorbed.bundle.libraries["lib-b"]?.backup, Data("backup-b".utf8))
        XCTAssertEqual(SecretAccounts.value(for: SecretAccounts.access("lib-a"), in: absorbed.bundle), Data("access-a".utf8))
        XCTAssertNil(SecretAccounts.value(for: SecretAccounts.retired("lib-b"), in: absorbed.bundle))
    }

    func testAnExistingBundleWinsOverALegacyCopy() throws {
        var current = SecretBundle()
        current.devicePrivateKey = Data("kept".utf8)
        current.libraries["lib-a"] = LibrarySecrets(access: Data("new".utf8))
        let items: [String: Data] = [
            SecretAccounts.bundle: try JSONEncoder().encode(current),
            SecretAccounts.device: Data("old".utf8),
            SecretAccounts.access("lib-a"): Data("old-access".utf8),
        ]
        let absorbed = SecretAccounts.absorb(items)
        XCTAssertEqual(absorbed.bundle.devicePrivateKey, Data("kept".utf8))
        XCTAssertEqual(absorbed.bundle.libraries["lib-a"]?.access, Data("new".utf8))
        XCTAssertEqual(absorbed.legacy, [SecretAccounts.device, SecretAccounts.access("lib-a")])
    }

    func testASecondReadUsesTheSessionAndSkipsTheSource() {
        let session = SecretSession()
        var reads = 0
        func load() -> SecretBundle {
            if let cached = session.current() { return cached }
            reads += 1
            let absorbed = SecretAccounts.absorb([
                SecretAccounts.access("lib-a"): Data("a".utf8),
                SecretAccounts.access("lib-b"): Data("b".utf8),
            ])
            session.store(absorbed.bundle)
            return absorbed.bundle
        }
        let first = load()
        let second = load()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second.libraries["lib-b"]?.access, Data("b".utf8))
        let updated = session.update { SecretAccounts.write(SecretAccounts.access("lib-a"), data: Data("renamed".utf8), into: &$0) }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(session.current(), updated)
        XCTAssertEqual(SecretAccounts.value(for: SecretAccounts.access("lib-a"), in: updated), Data("renamed".utf8))
    }

    func testThePromptGateIsTheVersionAndBuild() {
        XCTAssertFalse(KeychainPromptGate.needsHeadsUp(stored: "0.4 (12)", version: "0.4", build: "12"))
        XCTAssertTrue(KeychainPromptGate.needsHeadsUp(stored: nil, version: "0.4", build: "12"))
        XCTAssertTrue(KeychainPromptGate.needsHeadsUp(stored: "0.4 (12)", version: "0.4", build: "13"))
        XCTAssertEqual(KeychainPromptGate.token(version: "0.4", build: "13"), "0.4 (13)")
    }
}
