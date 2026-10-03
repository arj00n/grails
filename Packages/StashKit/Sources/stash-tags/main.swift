import Foundation
import StashKit

// Try the on-device auto-tagger on your own photos, to see what Stash would tag them with.
//   swift run -c release stash-tags [--sensitivity 0...1] [--raw] photo.jpg folder/ ...
var sensitivity = 0.5, showRaw = false, paths: [String] = []
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--sensitivity": sensitivity = args.popFirst().flatMap(Double.init) ?? sensitivity
    case "--raw": showRaw = true
    case "-h", "--help": print("usage: stash-tags [--sensitivity 0...1] [--raw] <image or folder>..."); exit(0)
    default: paths.append(a)
    }
}
guard !paths.isEmpty else { print("usage: stash-tags [--sensitivity 0...1] [--raw] <image or folder>..."); exit(2) }

let options = ImageTaggerOptions.sensitivity(sensitivity)
let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "bmp"]
var files: [URL] = []
for p in paths {
    let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { print("not found: \(p)"); continue }
    if isDir.boolValue {
        let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let f = en?.nextObject() as? URL { if exts.contains(f.pathExtension.lowercased()) { files.append(f) } }
    } else { files.append(url) }
}
print("confidence ≥ \(String(format: "%.2f", options.minConfidence)), at most \(options.maxTags) tags\n")
for f in files.sorted(by: { $0.path < $1.path }) {
    do {
        let tags = try ImageTagger.suggestions(forImageAt: f, options: options)
        print("\(f.lastPathComponent)\n  " + (tags.isEmpty ? "(no tags)" : tags.map { "\($0.tag) \(Int($0.confidence * 100))%" }.joined(separator: ", ")))
        if showRaw {
            let raw = try ImageTagger.rawLabels(forImageAt: f).prefix(12).map { "\($0.label) \(Int($0.confidence * 100))%" }
            print("  raw: " + raw.joined(separator: ", "))
        }
    } catch { print("\(f.lastPathComponent)\n  error: \(error.localizedDescription)") }
}
