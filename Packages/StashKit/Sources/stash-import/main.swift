import Foundation
import StashKit

// Import a public Are.na channel or Pinterest board.
//   stash-import <link>                       list what the board holds (downloads nothing)
//   stash-import <link> --into My.stash       import it into that library, into a collection named after the board
var args = Array(CommandLine.arguments.dropFirst())
var libraryPath: String?
if let i = args.firstIndex(of: "--into"), i + 1 < args.count { libraryPath = args[i + 1]; args.removeSubrange(i...(i + 1)) }
guard let link = args.first else { print("usage: stash-import <are.na or pinterest board link> [--into Library.stash]"); exit(2) }

let importer = BoardImporter()
do {
    let ref = try await importer.resolve(link)
    print("\(ref.service) \(ref.kindName): \(ref.webURL.absoluteString)")
    let board = try await importer.fetch(ref) { found, total in
        FileHandle.standardError.write(Data("\r  reading… \(found)\(total.map { " of \($0)" } ?? "")".utf8))
    }
    FileHandle.standardError.write(Data("\r                              \r".utf8))
    print("“\(board.name)”: \(board.entries.count) importable" + (board.expectedTotal.map { " of \($0)" } ?? ""))
    for (why, n) in board.skipped.sorted(by: { $0.key < $1.key }) { print("  skipping \(n) \(why)") }
    if let note = board.note { print("  note: \(note)") }
    guard let libraryPath else {
        let videos = board.entries.filter { $0.mediaUrls.first?.hasSuffix(".mp4") == true }
        print("  \(videos.count) video\(videos.count == 1 ? "" : "s")")
        for e in board.entries.prefix(8) { print("  - \(e.title ?? "(untitled)")  \(e.mediaUrls.first ?? e.pageUrl ?? "")\n      source: \(e.pageUrl ?? "-")") }
        for e in videos { print("  ▶ \(e.mediaUrls.first ?? "")  (+\(e.mediaUrls.count - 1) fallbacks)") }
        if board.entries.count > 8 { print("  … and \(board.entries.count - 8) more") }
        exit(0)
    }
    let store = try await LibraryStore.open(at: URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath), index: nil, userHandle: NSUserName())
    let service = LibraryCaptureService(store: { store })
    let summary = try await importer.run(board, into: store, service: service) { done, total in
        FileHandle.standardError.write(Data("\r  importing \(done) of \(total)".utf8))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    print(summary.headline)
} catch {
    print("error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
    exit(1)
}
