import Foundation

/// The "before" state of everything a user action touched. Applying it undoes the action, and applying it returns
/// the opposite change set (so redo is the same operation). `nil` means "did not exist before".
public struct ChangeSet: Sendable {
    public var label: String
    public var items: [String: Item?]
    public var collections: [String: StashCollection?]
    public var smartFolders: [String: SmartFolder?]
    /// board key → item id → the placement before the action (nil = it had none)
    public var canvases: [String: [String: CanvasPlacement?]]

    public var isEmpty: Bool { items.isEmpty && collections.isEmpty && smartFolders.isEmpty && canvases.isEmpty }

    public init(label: String, items: [String: Item?] = [:], collections: [String: StashCollection?] = [:], smartFolders: [String: SmartFolder?] = [:], canvases: [String: [String: CanvasPlacement?]] = [:]) {
        self.label = label; self.items = items; self.collections = collections; self.smartFolders = smartFolders; self.canvases = canvases
    }
}

struct ChangeRecorder {
    var items: [String: Item?] = [:]
    var collections: [String: StashCollection?] = [:]
    var smartFolders: [String: SmartFolder?] = [:]
    var canvases: [String: [String: CanvasPlacement?]] = [:]
}
