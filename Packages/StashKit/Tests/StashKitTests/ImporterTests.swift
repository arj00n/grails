import Foundation
import Testing
@testable import StashKit

@Suite struct ImporterTests {
    @Test func expandsFoldersRecursivelySkippingHiddenAndPackages() throws {
        let root = TestSupport.tempDir()
        let fm = FileManager.default
        func touch(_ rel: String) {
            let u = root.appendingPathComponent(rel)
            try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: u.path, contents: Data("x".utf8))
        }
        touch("a.png"); touch("sub/b.jpg"); touch("sub/deeper/c.gif"); touch(".hidden.png")
        touch("Old.stash/items/x/original.png")
        let loose = TestSupport.tempDir().appendingPathComponent("loose.png")
        fm.createFile(atPath: loose.path, contents: Data("x".utf8))

        let files = FolderScanner.expandFiles([root, loose, URL(fileURLWithPath: "/definitely/missing.png")])
        #expect(files.map(\.lastPathComponent) == ["a.png", "b.jpg", "c.gif", "loose.png"])
    }
}
