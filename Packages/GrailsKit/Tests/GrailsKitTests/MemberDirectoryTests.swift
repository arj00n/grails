import Foundation
import Testing
@testable import GrailsKit

@Suite struct MemberDirectoryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func person(_ handle: String, id: String, look: AvatarLook, name: String? = nil) -> MemberRecord {
        MemberRecord(handle: handle, firstSeen: now, lastSeen: now, name: name ?? handle, id: id, look: look)
    }

    @Test func lookChangeRefreshesThatMembersItemsOnly() {
        let ada = person("ada", id: "m-ada", look: AvatarLook(usesPhoto: false, tint: 1, character: 10), name: "Ada")
        let ben = person("ben", id: "m-ben", look: AvatarLook(usesPhoto: false, tint: 2, character: 20), name: "Ben")
        var directory = MemberDirectory(records: [ada, ben])
        var cache = MemberAvatarCache()
        let items = [
            MemberDirectory.Attribution(id: "lamp", addedBy: "ada"),
            MemberDirectory.Attribution(id: "chair", addedBy: "m-ben"),
        ]
        let before = cache.avatars(for: items, in: directory)

        var shuffled = ada
        shuffled.look = AvatarLook(usesPhoto: false, tint: 4, character: 99)
        let next = MemberDirectory(records: [shuffled, ben])
        let affected = next.changedTokens(from: directory)
        #expect(MemberDirectory.lists("ada", in: affected))
        #expect(MemberDirectory.lists("m-ada", in: affected))
        #expect(!MemberDirectory.lists("ben", in: affected))
        #expect(!MemberDirectory.lists("m-ben", in: affected))
        #expect(next.changedTokens(from: next).isEmpty)

        directory = next
        let adaAgain = cache.avatar(for: "Ada", in: directory)
        let benAgain = cache.avatar(for: "ben", in: directory)
        #expect(adaAgain?.reused == false)
        #expect(adaAgain?.avatar.character == 99)
        #expect(adaAgain?.avatar.tint == 4)
        #expect(benAgain?.reused == true)
        #expect(benAgain?.avatar == before["chair"])

        let after = cache.avatars(for: items, in: directory)
        #expect(after["lamp"]?.character == 99)
        #expect(after["lamp"]?.tint == 4)
        #expect(after["lamp"]?.usesPhoto == false)
        #expect(after["lamp"]?.revision != before["lamp"]?.revision)
        #expect(after["chair"] == before["chair"])
    }

    @Test func photoChangeRefreshesThatMemberOnly() {
        let ada = person("ada", id: "m-ada", look: AvatarLook(usesPhoto: true, tint: 1, character: 10))
        let ben = person("ben", id: "m-ben", look: AvatarLook(usesPhoto: true, tint: 2, character: 20))
        var directory = MemberDirectory(records: [ada, ben], photoStamps: [
            "m-ada": "old|ada.avatar.jpg|1",
            "m-ben": "ben|ben.avatar.jpg|1",
        ])
        var cache = MemberAvatarCache()
        let items = [
            MemberDirectory.Attribution(id: "lamp", addedBy: "ada"),
            MemberDirectory.Attribution(id: "chair", addedBy: "ben"),
        ]
        let before = cache.avatars(for: items, in: directory)
        directory = MemberDirectory(records: [ada, ben], photoStamps: [
            "m-ada": "new|ada.avatar.jpg|2",
            "m-ben": "ben|ben.avatar.jpg|1",
        ])
        let adaAgain = cache.avatar(for: "ada", in: directory)
        let benAgain = cache.avatar(for: "ben", in: directory)
        #expect(adaAgain?.reused == false)
        #expect(adaAgain?.avatar.usesPhoto == true)
        #expect(adaAgain?.avatar.revision != before["lamp"]?.revision)
        #expect(benAgain?.reused == true)
        #expect(benAgain?.avatar == before["chair"])

        let after = cache.avatars(for: items, in: directory)
        #expect(after["lamp"] == adaAgain?.avatar)
        #expect(after["chair"] == before["chair"])
    }

    @Test func savedLookIsWhatTheDirectoryResolves() throws {
        let root = TestSupport.tempDir("avatar-dir")
        let layout = LibraryLayout(root: root)
        try Members.setLook(AvatarLook(usesPhoto: false, tint: 1, character: 10), handle: "ada", in: layout, now: now)
        let first = MemberDirectory.load(in: layout)
        let before = try #require(first.portrait(matching: "Ada"))
        #expect(before.look?.character == 10)

        try Members.setLook(AvatarLook(usesPhoto: false, tint: 5, character: 42), handle: "ada", in: layout, now: now)
        let second = MemberDirectory.load(in: layout)
        let after = try #require(second.portrait(matching: "ada"))
        #expect(after.look?.character == 42)
        #expect(after.look?.tint == 5)
        #expect(after.revision != before.revision)
        #expect(MemberDirectory.lists("ada", in: second.changedTokens(from: first)))
    }

    @Test func memberPathsAreSeparateFromItemPaths() {
        let root = URL(fileURLWithPath: "/libraries/Studio.grails")
        #expect(MemberDirectory.pathsTouchMembers(["/libraries/Studio.grails/.members/m-ada.json"], root: root))
        #expect(MemberDirectory.pathsTouchMembers(["/libraries/Studio.grails/.members/m-ada.avatar.jpg"], root: root))
        #expect(!MemberDirectory.pathsTouchMembers(["/libraries/Studio.grails/items/abc/item.json"], root: root))
        #expect(!MemberDirectory.pathsTouchMembers([], root: root))
    }
}
