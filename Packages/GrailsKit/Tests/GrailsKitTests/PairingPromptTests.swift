import Foundation
import Testing
@testable import GrailsKit

@Suite struct PairingPromptTests {
    private let created = Date(timeIntervalSince1970: 1_700_000_000)
    private let line = "Save to Grails is asking to connect to this Mac."

    private func request(id: String, origin: String, created: Date) -> PairingBroker.Request {
        PairingBroker.Request(id: id, origin: origin, created: created, state: .pending)
    }

    private var safariOrigin: String {
        "safari-web-extension://AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    }

    @Test func chromeAndSafariCopy() {
        let chrome = PairingSheetItem(request(id: "c", origin: ExtensionOrigin.chrome, created: created), now: created)
        let safari = PairingSheetItem(request(id: "s", origin: safariOrigin, created: created), now: created)
        #expect(chrome?.copy.title == "Connect Chrome?")
        #expect(safari?.copy.title == "Connect Safari?")
        #expect(chrome?.copy.line == line)
        #expect(safari?.copy.line == line)
    }

    @Test func unreadableOriginDoesNotClaimTheNextRequest() {
        var session = PairingSession()
        let junk = request(id: "j", origin: "https://example.com", created: created)
        #expect(PairingSheetItem(junk, now: created) == nil)
        #expect(session.deliver(junk, now: created) == .clear("j"))
        let live = request(id: "a", origin: ExtensionOrigin.chrome, created: created)
        #expect(session.deliver(live, now: created) == .showInFront(live))
    }

    @Test func insideTheLifetimeAllowsAndDenies() {
        let item = PairingSheetItem(request(id: "a", origin: ExtensionOrigin.chrome, created: created), now: created)
        let almost = created.addingTimeInterval(PairingBroker.lifetime - 0.001)
        #expect(item != nil)
        guard let item else { return }
        guard case .allow(let allowance) = item.allowAnswer(now: almost) else {
            #expect(Bool(false))
            return
        }
        #expect(allowance.id == "a")
        #expect(!allowance.isExpired(now: almost))
        guard case .deny(let refusal) = item.denyAnswer(now: almost) else {
            #expect(Bool(false))
            return
        }
        #expect(refusal.id == "a")
    }

    @Test func atAndPastTheLifetimeTheSheetDisappearsAndTheIdIsNotClaimed() {
        let req = request(id: "e", origin: ExtensionOrigin.chrome, created: created)
        let at = created.addingTimeInterval(PairingBroker.lifetime)
        let past = created.addingTimeInterval(PairingBroker.lifetime + 1)
        #expect(PairingSheetItem(req, now: at) == nil)
        #expect(PairingSheetItem(req, now: past) == nil)
        let early = PairingSheetItem(req, now: created)
        #expect(early?.allowAnswer(now: at) == .expired("e"))
        #expect(early?.denyAnswer(now: past) == .expired("e"))
        if case .allow(let allowance) = early?.allowAnswer(now: created) {
            #expect(allowance.isExpired(now: at))
        } else {
            #expect(Bool(false))
        }
        var session = PairingSession()
        #expect(session.deliver(req, now: at) == .clear("e"))
        #expect(session.deliver(req, now: created) == .showInFront(req))
    }

    @Test func eachNewIdComesForwardOnce() {
        var session = PairingSession()
        let first = request(id: "a", origin: ExtensionOrigin.chrome, created: created)
        let second = request(id: "b", origin: safariOrigin, created: created)
        #expect(session.deliver(first, now: created) == .showInFront(first))
        #expect(session.deliver(first, now: created) == .show(first))
        #expect(session.deliver(second, now: created) == .showInFront(second))
        #expect(session.deliver(second, now: created) == .show(second))
    }

    @Test func remainingAndExpiredFollowTheBrokerLifetime() {
        let item = PairingSheetItem(request(id: "a", origin: ExtensionOrigin.chrome, created: created), now: created)
        #expect(item?.remaining(now: created) == PairingBroker.lifetime)
        let at = created.addingTimeInterval(PairingBroker.lifetime)
        #expect(item?.remaining(now: at) == 0)
        #expect(item?.expired(now: created.addingTimeInterval(PairingBroker.lifetime - 0.001)) == false)
        #expect(item?.expired(now: at) == true)
    }
}
