import Testing
@testable import GrailsKit

@Suite struct NotificationPolicyTests {
    @Test func addingAnItemNotifiesNobody() {
        let event = ActivityEvent.itemAdded(by: "bea")
        #expect(NotificationPolicy.notice(viewer: "ada", event: event) == nil)
        #expect(NotificationPolicy.notice(viewer: "bea", event: event) == nil)
        #expect(NotificationPolicy.lines(viewer: "ada", events: [event]).isEmpty)
    }

    @Test func aMentionOrTagNotifiesThatPersonOnly() {
        #expect(NotificationPolicy.notice(viewer: "ada", event: .mentioned(by: "bea", handle: "ada")) == .mention)
        #expect(NotificationPolicy.notice(viewer: "cam", event: .mentioned(by: "bea", handle: "ada")) == nil)
        #expect(NotificationPolicy.notice(viewer: "ada", event: .mentioned(by: "ada", handle: "ada")) == nil)
        #expect(NotificationPolicy.notice(viewer: "Ada", event: .tagged(by: "bea", handle: " ada ")) == .tag)
        #expect(NotificationPolicy.notice(viewer: "bea", event: .tagged(by: "bea", handle: "ada")) == nil)
        #expect(NotificationPolicy.lines(viewer: "ada", events: [.mentioned(by: "bea", handle: "ada"), .tagged(by: "cam", handle: "ada")]) == ["You were mentioned", "You were tagged"])
    }

    @Test func aCollectionNotifiesItsOwnerAndMembersButNotTheActor() {
        let stake = CollectionStake(owner: "ada", members: ["cam"])
        #expect(NotificationPolicy.notice(viewer: "ada", event: .addedToCollection(by: "bea", stake: stake)) == .collection)
        #expect(NotificationPolicy.notice(viewer: "cam", event: .addedToCollection(by: "bea", stake: stake)) == .collection)
        #expect(NotificationPolicy.notice(viewer: "bea", event: .addedToCollection(by: "bea", stake: stake)) == nil)
        #expect(NotificationPolicy.notice(viewer: "dee", event: .addedToCollection(by: "bea", stake: stake)) == nil)
        #expect(NotificationPolicy.notice(viewer: "ada", event: .addedToCollection(by: "ada", stake: stake)) == nil)
        let read = CollectionStakeRead.stake(owner: "ada", extras: ["members": .array([.string("cam")])])
        #expect(read == stake)
    }
}
