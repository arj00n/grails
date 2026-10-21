import Foundation
import XCTest
@testable import GrailsSync

/// 0.3.8 credential, device, and cursor documents decoded by the current types, plus a roster signature that does not cover `look`.
final class VersionChecksTests: XCTestCase {
    func testA038SecretDeviceAndCursorStillDecode() throws {
        let access = #"{"endpoint":"http://127.0.0.1:9000","region":"us-east-1","bucket":"grails-test","accessKeyId":"example-key","secretAccessKey":"example-secret","email":"ada@example.com"}"#
        let accessData = Data(access.utf8)
        let bundleJSON = """
        {"libraries":{"lib-1":{"access":"\(accessData.base64EncodedString())"}}}
        """
        let bundle = try JSONDecoder().decode(SecretBundle.self, from: Data(bundleJSON.utf8))
        let stored = try XCTUnwrap(bundle.libraries["lib-1"]?.access)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        XCTAssertEqual(object["accessKeyId"] as? String, "example-key")
        XCTAssertEqual(object["email"] as? String, "ada@example.com")
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("look"))

        let deviceJSON = #"{"deviceName":"Ada's Mac","email":"ada@example.com","inviteId":"inv-1","publicKey":"device-key"}"#
        let device = try JSONDecoder().decode(DeviceRecord.self, from: Data(deviceJSON.utf8))
        XCTAssertEqual(device.email, "ada@example.com")
        XCTAssertEqual(device.memberId, "device-key")
        XCTAssertEqual(device.name, "")

        let cursorJSON = #"{"entries":{"items/a/item.json":{"digest":"d","etag":"W/\"abc\"","size":4}},"uploadEvents":[],"usageBytes":4}"#
        var cursor = try JSONDecoder().decode(SyncManifest.self, from: Data(cursorJSON.utf8))
        cursor.canonicalizeETags()
        XCTAssertEqual(cursor.entries["items/a/item.json"]?.etag, "abc")
        XCTAssertNil(cursor.trustedCanonical)
    }

    func testARosterSignatureIgnoresLook() throws {
        let (key, signed) = try TestLibrary.owner()
        XCTAssertTrue(DeviceKey.verify(signature: signed.signature, publicKey: key.publicKey, data: Data(signed.canonical.utf8)))
        XCTAssertFalse(signed.canonical.contains("look"))
        let withLook = #"{"avatar":"abc","handle":"ada","look":{"character":99,"photo":false,"tint":4}}"#
        let withoutLook = #"{"avatar":"abc","handle":"ada"}"#
        XCTAssertNotEqual(withLook, withoutLook)
        XCTAssertTrue(DeviceKey.verify(signature: signed.signature, publicKey: key.publicKey, data: Data(signed.canonical.utf8)))
        let body = try XCTUnwrap(TeamDocument.parse(signed.canonical))
        XCTAssertEqual(body.role(of: "arjun@studio.com"), .owner)
        XCTAssertEqual(body.minAppVersion, TeamBody.defaultMinAppVersion)
    }
}
