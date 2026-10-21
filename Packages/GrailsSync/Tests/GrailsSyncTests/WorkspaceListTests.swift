import XCTest
import GrailsSync

final class WorkspaceListTests: XCTestCase {
    private let home = "/tmp/grails-workspace-tests"
    private let libraryID = "01M4TA7YWQKEEN4W8B5AEKRDXG"

    private var bucket: String {
        "\(home)/Library/Application Support/Grails/bucket/\(libraryID).grails"
    }

    private var drive: String {
        "\(home)/Library/CloudStorage/GoogleDrive-ada@example.com/Team Library.grails"
    }

    func testRememberReplacesByLibraryId() {
        let list = WorkspaceList.remember(
            [WorkspaceEntry(id: libraryID, path: drive, name: "Team Library", color: "#12A594")],
            id: libraryID, path: bucket, name: "Swish Design", home: home
        )
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, libraryID)
        XCTAssertEqual(list[0].path, bucket)
        XCTAssertEqual(list[0].name, "Swish Design")
        XCTAssertEqual(list[0].color, "#12A594")
    }

    func testRememberCollapsesRowsThatAlreadyShareAnId() {
        let list = WorkspaceList.remember([
            WorkspaceEntry(id: libraryID, path: drive, name: "Team Library", color: "#12A594"),
            WorkspaceEntry(id: libraryID, path: bucket, name: "Swish Design"),
        ], id: libraryID, path: bucket, name: "Swish Design", home: home)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, libraryID)
        XCTAssertEqual(list[0].path, bucket)
        XCTAssertEqual(list[0].name, "Swish Design")
        XCTAssertEqual(list[0].color, "#12A594")
    }

    func testRememberTreatsATildePathAsTheSameFolder() {
        let tilde = "~/Library/Application Support/Grails/bucket/\(libraryID).grails"
        let list = WorkspaceList.remember(
            [WorkspaceEntry(id: tilde, path: tilde, name: "Team Library", color: "#12A594")],
            id: libraryID, path: bucket, name: "Swish Design", home: home
        )
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, libraryID)
        XCTAssertEqual(list[0].path, bucket)
        XCTAssertEqual(list[0].name, "Swish Design")
        XCTAssertEqual(list[0].color, "#12A594")
    }

    func testRememberAppendsADifferentLibrary() {
        let otherID = "01OTHERLIBRARY00000000000"
        let other = WorkspaceEntry(id: otherID, path: "\(home)/Pictures/Other.grails", name: "Other")
        let list = WorkspaceList.remember([other], id: libraryID, path: bucket, name: "Swish Design", home: home)
        XCTAssertEqual(list.map(\.id), [otherID, libraryID])
    }

    func testLoadDedupesTheSavedListAndKeepsTheColour() throws {
        let json = """
        [{"path":"~/Library/Application Support/Grails/bucket/01M4TA7YWQKEEN4W8B5AEKRDXG.grails","name":"Swish Design","id":"01M4TA7YWQKEEN4W8B5AEKRDXG"},{"path":"~/Library/Application Support/Grails/bucket/01M4TA7YWQKEEN4W8B5AEKRDXG.grails","name":"Team Library","id":"01M4TA7YWQKEEN4W8B5AEKRDXG","color":"#12A594"}]
        """
        let decoded = try JSONDecoder().decode([WorkspaceEntry].self, from: Data(json.utf8))
        let open = "~/Library/Application Support/Grails/bucket/01M4TA7YWQKEEN4W8B5AEKRDXG.grails"
        let list = WorkspaceList.reconcile(decoded, openID: libraryID, openPath: open, home: home)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, libraryID)
        XCTAssertEqual(list[0].path, bucket)
        XCTAssertEqual(list[0].name, "Swish Design")
        XCTAssertEqual(list[0].color, "#12A594")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bucket + "/library.json"))
    }

    func testUnavailablePathStaysWithItsSavedName() {
        let path = "\(home)/unmounted/Team Library.grails"
        let saved = WorkspaceEntry(id: "01TEAMLIBRARY000000000000", path: path, name: "Studio Shelf", color: "#3E63DD")
        let list = WorkspaceList.reconcile([
            saved,
            WorkspaceEntry(id: libraryID, path: bucket, name: "Swish Design"),
        ], home: home)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].name, "Studio Shelf")
        XCTAssertEqual(list[0].path, path)
        XCTAssertEqual(list[0].color, "#3E63DD")
        XCTAssertFalse(WorkspaceList.isAvailable(path: path, home: home, fileExists: { _ in false }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
