import Foundation
import GrailsDesign
import Testing
@testable import GrailsKit

/// Member profile as 0.3.8 encodes it. Unknown keys, including `look`, are ignored and a save writes only these fields.
private struct MemberProfile038: Codable {
    var id: String
    var handle: String
    var name: String
    var previousHandles: [String]
    var firstSeen: Date
    var lastSeen: Date
    var avatar: String?

    enum CodingKeys: String, CodingKey { case id, handle, name, previousHandles, firstSeen, lastSeen, avatar }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        handle = try c.decode(String.self, forKey: .handle)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? handle
        previousHandles = try c.decodeIfPresent([String].self, forKey: .previousHandles) ?? []
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !id.isEmpty { try c.encode(id, forKey: .id) }
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
        if !previousHandles.isEmpty { try c.encode(previousHandles, forKey: .previousHandles) }
        try c.encode(firstSeen, forKey: .firstSeen)
        try c.encode(lastSeen, forKey: .lastSeen)
        try c.encodeIfPresent(avatar, forKey: .avatar)
    }
}

@Suite struct MixedVersionProfileTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let look = AvatarLook(usesPhoto: false, tint: 4, character: 99)

    @Test func anOlderClientDecodesAProfileAndKeepsTheLookFile() throws {
        let layout = try library()
        _ = try Members.adopt(name: "Ada", previous: "", memberId: "m-ada", in: layout, now: now)
        _ = try Members.setLook(look, handle: "Ada", in: layout, now: now)
        let url = try #require(Members.profileURL(id: "m-ada", in: layout))
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!text.contains("\"look\""))

        let older = try GrailsJSON.decode(MemberProfile038.self, from: Data(contentsOf: url))
        #expect(older.id == "m-ada")
        #expect(older.name == "Ada")

        var edited = older
        edited.lastSeen = now.addingTimeInterval(30)
        edited.name = "Ada"
        try AtomicFile.writeJSON(edited, to: url)

        let again = try #require(Members.profile(matching: "m-ada", in: layout))
        #expect(again.look == look)
        #expect(again.avatar == nil)
    }

    @Test func anInlineLookMovesBesideTheProfileBeforeAnOlderSave() throws {
        let layout = try library()
        var object = try #require(try JSONSerialization.jsonObject(with: GrailsJSON.encode(MemberRecord(handle: "ada", firstSeen: now, lastSeen: now, name: "Ada", id: "m-ada"))) as? [String: Any])
        object["look"] = ["photo": false, "tint": 4, "character": 99]
        try FileManager.default.createDirectory(at: Members.folder(layout), withIntermediateDirectories: true)
        let url = Members.folder(layout).appendingPathComponent("m-ada.json")
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)

        let loaded = try #require(Members.profile(matching: "m-ada", in: layout))
        #expect(loaded.look == look)
        _ = try Members.record(handle: "Ada", in: layout, now: now.addingTimeInterval(1), minInterval: 0)
        let stored = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!stored.contains("\"look\""))
        #expect(FileManager.default.fileExists(atPath: Members.lookURL(beside: url).path))

        let older = try GrailsJSON.decode(MemberProfile038.self, from: Data(contentsOf: url))
        var edited = older
        edited.lastSeen = now.addingTimeInterval(40)
        try AtomicFile.writeJSON(edited, to: url)
        let again = try #require(Members.profile(matching: "m-ada", in: layout))
        #expect(again.look == look)
    }

    @Test func aProfileWithoutALookUsesTheMemberId() throws {
        let layout = try library()
        let record = MemberRecord(handle: "ada", firstSeen: now, lastSeen: now, name: "Ada", id: "m-ada")
        try FileManager.default.createDirectory(at: Members.folder(layout), withIntermediateDirectories: true)
        let url = Members.folder(layout).appendingPathComponent("m-ada.json")
        try AtomicFile.writeJSON(record, to: url)
        let found = try #require(Members.profile(matching: "m-ada", in: layout))
        #expect(found.look == nil)
        let face = DitherAvatarSpec(memberID: found.id, name: found.name)
        let again = DitherAvatarSpec(memberID: "m-ada", name: "Ada")
        #expect(face == again)
        #expect(face != DitherAvatarSpec(memberID: "m-bea", name: "Ada"))
    }

    private func library() throws -> LibraryLayout {
        LibraryLayout(root: TestSupport.tempDir("mixed-profile"))
    }
}
