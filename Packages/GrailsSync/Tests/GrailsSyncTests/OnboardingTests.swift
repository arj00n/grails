import Foundation
import XCTest
import GrailsSync

final class OnboardingTests: XCTestCase {
    func testThreeStepsThenDone() {
        var flow = TeammateOnboarding()
        XCTAssertEqual(TeammateOnboarding.stepCount, 3)
        XCTAssertEqual(flow.step, .link)
        XCTAssertEqual(flow.stepNumber, 1)
        XCTAssertEqual(flow.title, "Invite link")
        flow.submitLink("see grails://join?id=inv1&blob=abc thanks")
        XCTAssertEqual(flow.step, .code)
        XCTAssertEqual(flow.link?.id, "inv1")
        XCTAssertEqual(flow.stepNumber, 2)
        flow.submitCode(" 042817 ")
        XCTAssertEqual(flow.step, .name)
        XCTAssertEqual(flow.code, "042817")
        XCTAssertEqual(flow.stepNumber, 3)
        XCTAssertEqual(flow.title, "Your name")
        XCTAssertFalse(flow.canContinue)
        flow.noteInvite(email: "Ada@Studio.com", suggestedName: "Ada Lovelace")
        XCTAssertEqual(flow.invitedEmail, "ada@studio.com")
        XCTAssertEqual(flow.displayName, "Ada Lovelace")
        XCTAssertTrue(flow.submitName("  Ada Lovelace  "))
        XCTAssertFalse(flow.submitName("   "))
        XCTAssertEqual(flow.displayName, "Ada Lovelace")
        flow.finish()
        XCTAssertEqual(flow.step, .done)
    }

    func testBadCodeStaysOnTheCodeStep() {
        var flow = TeammateOnboarding()
        flow.submitLink("grails://join?id=inv1&blob=abc")
        flow.submitCode("123")
        XCTAssertEqual(flow.step, .code)
        XCTAssertEqual(flow.error, .badCode)
        XCTAssertEqual(flow.message, "That code doesn't match. Check it and try again.")
        XCTAssertTrue(flow.canContinue)
        flow.submitCode("042817")
        XCTAssertEqual(flow.step, .name)
        XCTAssertNil(flow.error)
    }

    func testExpiredAlreadyUsedAndOutdatedBlock() {
        var expired = reachedEmail()
        expired.fail(.expired)
        XCTAssertEqual(expired.step, .name)
        XCTAssertEqual(expired.message, "This invite has expired. Ask for a new one.")
        XCTAssertFalse(expired.canContinue)

        var used = reachedEmail()
        used.fail(TeammateOnboarding.error(from: .alreadyRedeemed))
        XCTAssertEqual(used.error, .alreadyUsed)
        XCTAssertEqual(used.message, "This invite has already been used. Ask for a new one.")
        XCTAssertFalse(used.canContinue)

        var old = reachedEmail()
        let gate = TeammateOnboarding.formatGate(app: "0.3.5", minimum: "9.0.0")
        XCTAssertEqual(gate, .outdated(minAppVersion: "9.0.0", appVersion: "0.3.5"))
        old.fail(gate!)
        XCTAssertEqual(old.step, .blocked)
        XCTAssertEqual(old.title, "Update Grails")
        XCTAssertEqual(old.message, "Update Grails")
        XCTAssertFalse(old.canContinue)
        old.finish()
        XCTAssertEqual(old.step, .blocked)

        XCTAssertNil(TeammateOnboarding.formatGate(app: "9.0.0", minimum: "0.3.5"))
        XCTAssertEqual(TeammateOnboarding.error(from: .wrongCode), .badCode)
        XCTAssertEqual(TeammateOnboarding.error(from: .locked).messageVia(), "Too many wrong codes. Ask for a new invite.")
    }

    func testBackMovesOneStep() {
        var flow = reachedEmail()
        flow.back()
        XCTAssertEqual(flow.step, .code)
        flow.back()
        XCTAssertEqual(flow.step, .link)
        flow.submitLink("not a link")
        XCTAssertEqual(flow.error, .malformed)
        XCTAssertEqual(flow.message, "That link looks incomplete. Copy it again from the invite.")
    }

    func testBlankNameDoesNotFinishAndALaterEditReplacesIt() {
        var flow = reachedEmail()
        flow.finish()
        XCTAssertEqual(flow.step, .name)
        XCTAssertTrue(flow.submitName("Ada"))
        flow.finish()
        XCTAssertEqual(flow.step, .done)
    }

    private func reachedEmail() -> TeammateOnboarding {
        var flow = TeammateOnboarding()
        flow.submitLink("grails://join?id=inv1&blob=abc")
        flow.submitCode("042817")
        return flow
    }
}

private extension TeammateJoinError {
    func messageVia() -> String? {
        var flow = TeammateOnboarding()
        flow.submitLink("grails://join?id=inv1&blob=abc")
        flow.fail(self)
        return flow.message
    }
}
