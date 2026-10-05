import Foundation
import StashKit

// Export a library (or its first N items) as a web page, the same page Stash's File ▸ Export as Web Page makes.
//   stash-share <Library.stash> <output folder> [--limit N] [--clusters N] [--title "Name"] [--no-zip] [--no-sources]
// --clusters N splits the items into N titled clusters, to see the sections and canvas view.
var args = Array(CommandLine.arguments.dropFirst())
@MainActor func take(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
@MainActor func has(_ flag: String) -> Bool { if let i = args.firstIndex(of: flag) { args.remove(at: i); return true }; return false }
let limit = take("--limit").flatMap(Int.init) ?? 200
let clusterCount = take("--clusters").flatMap(Int.init) ?? 0
let title = take("--title") ?? "Stash export"
let noZip = has("--no-zip"), noSources = has("--no-sources")
guard args.count == 2 else { print("usage: stash-share <Library.stash> <output folder> [--limit N] [--clusters N] [--title Name] [--no-zip] [--no-sources]"); exit(2) }

do {
    let store = try await LibraryStore.open(at: URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath), index: nil, userHandle: NSUserName())
    var q = ItemQuery()
    q.limit = limit
    let ids = try await store.index.query(q).map(\.id)
    var clusters: [CanvasCluster] = []
    if clusterCount > 0 {
        let per = max(1, (ids.count + clusterCount - 1) / clusterCount)
        for (n, chunk) in stride(from: 0, to: ids.count, by: per).map({ Array(ids[$0..<min($0 + per, ids.count)]) }).enumerated() {
            clusters.append(CanvasCluster(title: n == 1 ? "" : "Cluster \(n + 1)", x: Double(n % 2) * 2000, y: Double(n / 2) * 1800, width: 1800, tile: 240, items: chunk))
        }
    }
    let out = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let r = try await store.exportWebPage(title: title, ids: ids, clusters: clusters, options: .init(includeSources: !noSources, makeZip: !noZip), to: out) { done, total in
        FileHandle.standardError.write(Data("\r  \(done) of \(total)".utf8))
    }
    print("\nExported \(r.exported) items (\(r.thumbnailOnly) thumbnail-only, \(r.skipped) skipped), \(r.bytes / 1_000_000) MB → \(r.folder.path)")
    if let z = r.zip { print("Zip: \(z.path)") }
} catch {
    print("error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
    exit(1)
}
