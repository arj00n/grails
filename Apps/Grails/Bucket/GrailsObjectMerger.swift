import Foundation
import GrailsKit
import GrailsSync

/// Folds two copies with the same rules Drive conflict copies already use.
/// Items union tags. Canvas keeps the newer placement and cluster. Collections and notes are whole-file, and a tie keeps the local collection or the incoming note.
struct GrailsObjectMerger: ObjectMerger {
    func merge(key: String, local: Data, remote: Data) -> Data {
        if key.hasSuffix("/item.json"),
           let left = try? GrailsJSON.decode(Item.self, from: local),
           let right = try? GrailsJSON.decode(Item.self, from: remote),
           let merged = try? GrailsJSON.encode(ConflictMerger.merge(left, right)) {
            return merged
        }
        if key.hasPrefix("canvas/"), key.hasSuffix(".json"),
           let left = try? GrailsJSON.decode(CanvasBoard.self, from: local),
           let right = try? GrailsJSON.decode(CanvasBoard.self, from: remote) {
            return (try? GrailsJSON.encodeCompact(CanvasBoard.merge(left, right))) ?? local
        }
        if key.hasPrefix("collections/"), key.hasSuffix(".json"),
           let left = try? GrailsJSON.decode(GrailsCollection.self, from: local),
           let right = try? GrailsJSON.decode(GrailsCollection.self, from: remote) {
            let winner = left.updatedAt >= right.updatedAt ? left : right
            if let merged = try? GrailsJSON.encode(winner) { return merged }
        }
        if key.hasPrefix("notes/"), key.hasSuffix(".json"),
           let left = try? GrailsJSON.decode(GrailsNote.self, from: local),
           let right = try? GrailsJSON.decode(GrailsNote.self, from: remote) {
            let localStamp = max(left.at, left.deletedAt ?? .distantPast)
            let remoteStamp = max(right.at, right.deletedAt ?? .distantPast)
            let winner = localStamp > remoteStamp ? left : right
            if let merged = try? GrailsJSON.encode(winner) { return merged }
        }
        return remote
    }
}
