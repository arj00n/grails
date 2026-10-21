import Foundation
import Testing
@testable import GrailsKit

@Suite struct AvatarLookTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A profile as an older Grails writes it: no `look`, and for the oldest, no `id` or `name` either.
    private func legacyJSON(dropping keys: [String]) throws -> Data {
        let record = MemberRecord(handle: "ada", firstSeen: now, lastSeen: now, name: "Ada", avatar: "abc", id: "m-ada")
        let data = try GrailsJSON.encode(record)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in keys { object[key] = nil }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func legacyMembersLoadWithNoLook() throws {
        let modern = try GrailsJSON.decode(MemberRecord.self, from: legacyJSON(dropping: ["look"]))
        #expect(modern.look == nil)
        #expect(modern.id == "m-ada")
        #expect(modern.avatar == "abc")

        let oldest = try GrailsJSON.decode(MemberRecord.self, from: legacyJSON(dropping: ["look", "id", "name", "previousHandles", "avatar"]))
        #expect(oldest.look == nil)
        #expect(oldest.id.isEmpty)
        #expect(oldest.name == "ada")
    }

    @Test func legacyMembersLoadFromTheFolder() throws {
        let root = TestSupport.tempDir("look-legacy")
        let layout = LibraryLayout(root: root)
        try FileManager.default.createDirectory(at: Members.folder(layout), withIntermediateDirectories: true)
        try legacyJSON(dropping: ["look", "id"]).write(to: Members.folder(layout).appendingPathComponent("ada.json"))
        let found = try #require(Members.profile(matching: "Ada", in: layout))
        #expect(found.look == nil)
        #expect(Members.all(in: layout).count == 1)
    }

    @Test func aBrokenLookCostsOnlyTheLook() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: legacyJSON(dropping: [])) as? [String: Any])
        object["look"] = "not an object"
        let record = try GrailsJSON.decode(MemberRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(record.look == nil)
        #expect(record.name == "Ada")

        object["look"] = ["photo": "yes", "tint": "three", "character": "seven"]
        let partial = try GrailsJSON.decode(MemberRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(partial.look == AvatarLook(usesPhoto: false, tint: nil, character: nil))
    }

    @Test func lookRoundTripsAndOmitsWhenUnset() throws {
        var record = MemberRecord(handle: "ada", firstSeen: now, lastSeen: now, name: "Ada", id: "m-ada")
        let bare = String(decoding: try GrailsJSON.encode(record), as: UTF8.self)
        #expect(!bare.contains("look"))
        record.look = AvatarLook(usesPhoto: false, tint: 3, character: 123_456)
        let data = try GrailsJSON.encode(record)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"look\""))
        let root = TestSupport.tempDir("look-round")
        let layout = LibraryLayout(root: root)
        _ = try Members.setLook(record.look!, handle: "ada", in: layout, now: now)
        let found = try #require(Members.profile(matching: "ada", in: layout))
        #expect(found.look == AvatarLook(usesPhoto: false, tint: 3, character: 123_456))
        let stored = String(decoding: try Data(contentsOf: Members.folder(layout).appendingPathComponent("ada.json")), as: UTF8.self)
        #expect(!stored.contains("\"look\""))
        #expect(!stored.contains("glyph"))
    }

    /// Looks written by older versions: a single letter, or a creature's seed. They still load, and each picks a face.
    @Test func aLegacyGlyphLookLoadsAsACharacter() throws {
        func decode(_ look: [String: Any]) throws -> AvatarLook? {
            var object = try #require(try JSONSerialization.jsonObject(with: legacyJSON(dropping: [])) as? [String: Any])
            object["look"] = look
            return try GrailsJSON.decode(MemberRecord.self, from: JSONSerialization.data(withJSONObject: object)).look
        }
        let old = try #require(try decode(["photo": false, "tint": 2, "glyph": "A"]))
        #expect(old.usesPhoto == false && old.tint == 2)
        let character = try #require(old.character)
        #expect(character >= 0 && character <= 0x7FFF_FFFF)
        #expect(character == AvatarLook.legacyCharacter("A"), "the same letter is the same creature on every Mac")
        #expect(try decode(["photo": true, "glyph": "  Ab"])?.character == character, "only the first visible character counts")
        #expect(try decode(["photo": true, "glyph": "B"])?.character != character)
        #expect(try decode(["photo": true, "glyph": "   "]) == AvatarLook(usesPhoto: true), "blank keeps the id's character")
        #expect(try decode(["glyph": "A", "character": 9])?.character == 9, "a new choice wins over the old one")
        let creature = try #require(try decode(["photo": false, "tint": 13, "character": 2_000_000_000]))
        #expect(creature == AvatarLook(usesPhoto: false, tint: 13, character: 2_000_000_000), "a creature-era seed loads as is and draws a blob")
        #expect(AvatarLook.legacyCharacter("👩‍🎨x") == AvatarLook.legacyCharacter("👩‍🎨"))
    }

    @Test func shuffleAlwaysGivesANewCharacter() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let next = AvatarLook.shuffled(from: 5, using: &rng)
            #expect(next != 5 && next >= 0 && next <= 0x7FFF_FFFF)
        }
    }

    @Test func shuffleAlwaysGivesANewColour() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let next = AvatarLook.shuffledTint(from: 3, count: 14, using: &rng)
            #expect(next != 3 && (0..<14).contains(next))
        }
        #expect(AvatarLook.shuffledTint(from: 0, count: 1, using: &rng) == 0, "one colour has nowhere else to go")
    }

    @Test func chooseClearAndReuploadAPhoto() throws {
        let root = TestSupport.tempDir("look-photo")
        let layout = LibraryLayout(root: root)
        _ = try Members.adopt(name: "Ada", previous: "", memberId: "m-ada", in: layout, now: now)
        try AvatarStore.place(jpeg: Data("jpeg".utf8), handle: "Ada", in: layout, now: now)
        let photo = try #require(AvatarStore.memberPhotoURL(id: "m-ada", in: layout))
        #expect(FileManager.default.fileExists(atPath: photo.path))

        try Members.setLook(AvatarLook(usesPhoto: true, tint: 2, character: 77), handle: "Ada", in: layout, now: now)
        try AvatarStore.clear(handle: "Ada", in: layout, now: now)
        let cleared = try #require(Members.profile(matching: "Ada", in: layout))
        #expect(!FileManager.default.fileExists(atPath: photo.path))
        #expect(cleared.avatar == nil)
        #expect(cleared.look == AvatarLook(usesPhoto: false, tint: 2, character: 77))

        try AvatarStore.place(jpeg: Data("jpeg2".utf8), handle: "Ada", in: layout, now: now)
        let back = try #require(Members.profile(matching: "Ada", in: layout))
        #expect(back.look?.usesPhoto == true)
        #expect(back.look?.tint == 2)
        #expect(back.look?.character == 77)
        #expect(Members.profiles(in: layout).count == 1)
    }
}
