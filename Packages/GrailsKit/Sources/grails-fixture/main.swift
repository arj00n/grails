import Foundation
import GrailsKit

let args = CommandLine.arguments
// grails-fixture <output.grails> <item-count>          synthetic items for performance tests
// grails-fixture --from-folder <folder> <output.grails> [max]   a real library made from a folder of images (copies them)
if args.count >= 4, args[1] == "--from-folder" {
    let folder = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
    let max = args.count > 4 ? Int(args[4]) ?? .max : .max
    let store = try LibraryStore.create(at: out, name: out.deletingPathExtension().lastPathComponent, index: try LibraryIndex(path: nil), userHandle: "demo")
    let files = FolderScanner.expandFiles([folder]).sorted { $0.path < $1.path }.prefix(max)
    var n = 0
    for f in files { if (try? await store.addItem(fileAt: f)) != nil { n += 1 } }
    print("imported \(n) of \(files.count) files into \(out.path)")
    exit(0)
}
guard args.count >= 3, let count = Int(args[2]) else {
    print("usage: grails-fixture <output.grails> <item-count>\n       grails-fixture --from-folder <folder> <output.grails> [max]")
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let start = Date()
try FixtureLibrary.generate(at: url, count: count)
print("wrote \(count) items to \(url.path) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
