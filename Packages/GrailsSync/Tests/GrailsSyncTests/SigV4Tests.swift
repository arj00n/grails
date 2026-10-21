import Foundation
import XCTest
import GrailsSync

final class SigV4Tests: XCTestCase {
    func testPublishedIAMVector() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2015, month: 8, day: 30, hour: 12, minute: 36, second: 0))!
        let url = URL(string: "https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08")!
        let authorization = AWSSigV4.authorization(.init(
            method: "GET",
            url: url,
            headers: [
                "content-type": "application/x-www-form-urlencoded; charset=utf-8",
                "host": "iam.amazonaws.com",
                "x-amz-date": "20150830T123600Z",
            ],
            body: Data(),
            date: date,
            region: "us-east-1",
            service: "iam",
            accessKey: "AKIDEXAMPLE",
            secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        ))
        XCTAssertEqual(
            authorization,
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7"
        )
    }

    func testEmptyBodyHash() {
        XCTAssertEqual(AWSSigV4.payloadHash(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSHA256Vectors() {
        XCTAssertEqual(Digests.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(R2Secret.accessSecret(tokenValue: "cf-token-value"), "ea18fb75a99ff16fb3fd54b6bf9983daa6fa7b53e13720f2248b5b71c5bbcd55")
    }

    func testPBKDF2Vector() {
        let once = Digests.pbkdf2SHA256(password: Data("password".utf8), salt: Data("salt".utf8), iterations: 1)
        XCTAssertEqual(Digests.hex(once), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let derived = Digests.pbkdf2SHA256(password: Data("password".utf8), salt: Data("salt".utf8), iterations: 4096)
        XCTAssertEqual(Digests.hex(derived), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    func testInviteIterationsStayHigh() {
        XCTAssertGreaterThanOrEqual(InviteCrypto.iterations, 100_000)
    }

    func testCredentialsStayRedacted() {
        let credentials = S3Credentials(accessKeyId: "AKID", secretAccessKey: "SECRET-VALUE-do-not-leak-9f3a")
        XCTAssertFalse(String(describing: credentials).contains("SECRET-VALUE-do-not-leak-9f3a"))
        XCTAssertFalse(String(reflecting: credentials).contains("SECRET-VALUE-do-not-leak-9f3a"))
        let key = DeviceKey()
        XCTAssertFalse(String(describing: key).contains(key.privateRaw.base64EncodedString()))
    }
}
