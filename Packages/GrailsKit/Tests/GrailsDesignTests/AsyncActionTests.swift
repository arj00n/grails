import Testing
@testable import GrailsDesign

@Suite struct AsyncActionTests {
    @Test func aSecondTapIsIgnoredAndFailureKeepsRetry() {
        var actions = GrailsAsyncActions()
        let started = actions.begin("cam@company.com", label: "Removing…")
        let again = actions.begin("cam@company.com", label: "Removing…")
        #expect(started)
        #expect(actions.isBusy("cam@company.com"))
        #expect(actions.label("cam@company.com") == "Removing…")
        #expect(!again)
        actions.fail("cam@company.com", message: "Couldn't remove them")
        #expect(!actions.isBusy("cam@company.com"))
        #expect(actions.label("cam@company.com") == nil)
        #expect(actions.failure("cam@company.com") == "Couldn't remove them")
        #expect(actions.statusLabel("cam@company.com") == "Removing…")
        let retried = actions.begin("cam@company.com", label: "Removing…")
        #expect(retried)
        actions.succeed("cam@company.com")
        #expect(actions.failure("cam@company.com") == nil)
        #expect(actions.statusLabel("cam@company.com") == nil)
    }
}
