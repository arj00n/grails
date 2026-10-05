import Foundation

/// The "before" state of everything a user action touched. Applying it undoes the action, and applying it returns
/// the opposite change set (so redo is the same operation). `nil` means "did not exist before".
public struct ChangeSet: Sendable {
    public var label: String
    public var items: [String: Item?]
    public var collections: [String: GrailsCollection?]
    public var smartFolders: [String: SmartFolder?]
    /// board key → item id → the placement before the action (nil = it had none)
    public var canvases: [String: [String: CanvasPlacement?]]
    /// board key → the board's clusters before the action
    public var clusters: [String: [CanvasCluster]]

    public var isEmpty: Bool { items.isEmpty && collections.isEmpty && smartFolders.isEmpty && canvases.isEmpty && clusters.isEmpty }

    public init(label: String, items: [String: Item?] = [:], collections: [String: GrailsCollection?] = [:], smartFolders: [String: SmartFolder?] = [:], canvases: [String: [String: CanvasPlacement?]] = [:], clusters: [String: [CanvasCluster]] = [:]) {
        self.label = label; self.items = items; self.collections = collections; self.smartFolders = smartFolders; self.canvases = canvases; self.clusters = clusters
    }
}

struct ChangeRecorder {
    var items: [String: Item?] = [:]
    var collections: [String: GrailsCollection?] = [:]
    var smartFolders: [String: SmartFolder?] = [:]
    var canvases: [String: [String: CanvasPlacement?]] = [:]
    var clusters: [String: [CanvasCluster]] = [:]
}
