import Foundation
import StashKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// Try the on-device auto-tagger on your own photos, to see what Stash would tag them with.
//   swift run -c release stash-tags [--sensitivity 0...1] [--raw | --simulate] photo.jpg folder/ ...
//   --simulate imports everything into a throwaway library and runs the real bulk auto-tagger, including learning
//   which tags are too common to be useful in that library. Your files are copied, never modified.
var sensitivity = 0.5, showRaw = false, simulate = false, engine = "auto", paths: [String] = []
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--sensitivity": sensitivity = args.popFirst().flatMap(Double.init) ?? sensitivity
    case "--raw": showRaw = true
    case "--simulate": simulate = true
    case "--engine": engine = args.popFirst() ?? engine        // auto | vision | model
    case "-h", "--help": print("usage: stash-tags [--sensitivity 0...1] [--raw | --simulate] <image or folder>..."); exit(0)
    default: paths.append(a)
    }
}
guard !paths.isEmpty else { print("usage: stash-tags [--sensitivity 0...1] [--raw | --simulate] <image or folder>..."); exit(2) }

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
if simulate {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("stash-tags-\(UUID().uuidString).stash")
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let store = try LibraryStore.create(at: root, name: "Simulation", index: try LibraryIndex(path: nil), userHandle: "sim")
        for f in files { _ = try await store.addItem(fileAt: f) }
        let tagger = AutoTagger(store: store, options: options)
        let t0 = Date()
        let summary = await tagger.run()
        let counts = try await store.index.tagCounts()
        let total = try await store.index.count(ItemQuery())
        print("\(total) items tagged in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s: \(summary.tagged) got tags, \(summary.tagsAdded) tags added, \(summary.failed) failed")
        print("learned to skip here (on too many items to help): " + (summary.learned.isEmpty ? "none" : summary.learned.joined(separator: ", ")) + " (removed \(summary.pruned) times)")
        print("\nwhat's left, most common first:")
        for c in counts.prefix(40) { print("  \(c.tag) ×\(c.count)") }
        let untagged = try await store.index.count({ var q = ItemQuery(); q.untagged = true; return q }())
        print("\n\(untagged) of \(total) items have no tags")
    } catch { print("simulation failed: \(error)") }
    exit(0)
}
print("engine: \(engine == "auto" ? AutoTagger.engineName : engine)  ·  confidence ≥ \(String(format: "%.2f", options.minConfidence)), at most \(options.maxTags) tags\n")
for f in files.sorted(by: { $0.path < $1.path }) {
    do {
        let t0 = Date()
        var tags: [TagSuggestion]
        switch engine {
        case "vision": tags = try ImageTagger.suggestions(forImageAt: f, options: options)
        case "model":
            #if canImport(FoundationModels)
            if #available(macOS 27.0, *) { tags = try await LanguageModelTagger.suggestions(forImageAt: f, options: options) } else { tags = [] }
            #else
            tags = []
            #endif
        default: tags = try await AutoTagger.automatic(f, options)
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        print("\(f.lastPathComponent)  [\(ms) ms]\n  " + (tags.isEmpty ? "(no tags)" : tags.map { engine == "vision" ? "\($0.tag) \(Int($0.confidence * 100))%" : $0.tag }.joined(separator: ", ")))
        if showRaw {
            let raw = try ImageTagger.rawLabels(forImageAt: f).prefix(12).map { "\($0.label) \(Int($0.confidence * 100))%" }
            print("  raw: " + raw.joined(separator: ", "))
        }
    } catch { print("\(f.lastPathComponent)\n  error: \(error.localizedDescription)") }
}
