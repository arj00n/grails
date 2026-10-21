import Foundation
import XCTest
@testable import GrailsSync

final class LibraryDeletionTests: XCTestCase {
    private struct Offline: Error {}

    func testAFailedRemoteDeleteKeepsTheCredentials() async {
        var forgot = false
        do {
            try await LibraryDeletion.run {
                throw Offline()
            } forget: {
                forgot = true
            }
            XCTFail("the failure reaches the caller")
        } catch {
            XCTAssertTrue(error is Offline)
        }
        XCTAssertFalse(forgot, "this Mac can still reach the library")
    }

    func testTheCredentialsGoOnlyAfterTheBucketIsEmpty() async throws {
        let store = MemoryObjectStore()
        await store.seed("library.json", body: Data("{}".utf8))
        await store.seed("items/a/item.json", body: Data("{}".utf8))
        var leftWhenForgot: [String]?
        try await LibraryDeletion.run {
            for head in try await store.list(prefix: "") { try await store.delete(head.key) }
        } forget: {
            leftWhenForgot = []
        }
        XCTAssertEqual(leftWhenForgot, [])
        let left = await store.keys()
        XCTAssertEqual(left, [])
    }
}
