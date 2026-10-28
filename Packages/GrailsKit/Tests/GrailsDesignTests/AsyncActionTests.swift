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

    @MainActor final class Row { var actions = GrailsAsyncActions() }

    /// Resend: the row is busy from the click, names each step, and a second click starts nothing.
    @MainActor @Test func stepsKeepTheRowBusyToTheEnd() async {
        let row = Row()
        var seen: [String?] = []
        var second = true
        let done = await GrailsAsyncActions.run("invite-1", on: row, \.actions, steps: [
            GrailsActionStep("Making new invite…") {
                seen.append(row.actions.label("invite-1"))
                second = await GrailsAsyncActions.run("invite-1", on: row, \.actions, steps: [GrailsActionStep("Making new invite…") { Issue.record("ran twice"); return nil }])
                return nil
            },
            GrailsActionStep("Revoking old invite…") {
                seen.append(row.actions.label("invite-1"))
                return nil
            },
        ])
        #expect(done)
        #expect(!second)
        #expect(seen == ["Making new invite…", "Revoking old invite…"])
        #expect(!row.actions.isBusy("invite-1"))
        #expect(row.actions.failure("invite-1") == nil)
    }

    @MainActor @Test func aFailedStepStopsAndStaysOnTheRow() async {
        let row = Row()
        let done = await GrailsAsyncActions.run("invite-1", on: row, \.actions, steps: [
            GrailsActionStep("Making new invite…") { "Couldn't create the invite" },
            GrailsActionStep("Revoking old invite…") { Issue.record("revoked after a failed invite"); return nil },
        ])
        #expect(!done)
        #expect(!row.actions.isBusy("invite-1"))
        #expect(row.actions.failure("invite-1") == "Couldn't create the invite")
        #expect(row.actions.statusLabel("invite-1") == "Making new invite…")
    }
}
