import Testing
@testable import StashKit

@Test func schemaVersionIsOne() {
    #expect(StashKit.schemaVersion == 1)
}
