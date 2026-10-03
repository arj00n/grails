import Foundation
import StashKit

let args = CommandLine.arguments
guard args.count >= 3, let count = Int(args[2]) else {
    print("usage: stash-fixture <output.stash> <item-count>")
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let start = Date()
try FixtureLibrary.generate(at: url, count: count)
print("wrote \(count) items to \(url.path) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
