import AppKit
import GrailsDesign
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// The app's bundle id (`$(GRAILS_BUNDLE_PREFIX).grails`). Type ids, the keychain service and the cache folder hang off it,
    /// so a fork with its own prefix never shares them with the official build.
    static let grailsAppID = Bundle.main.bundleIdentifier ?? "xyz.arjoon.grails"
    static let grailsLibrary = UTType("\(grailsAppID).library")
    static let grailsItems = UTType(exportedAs: "\(grailsAppID).items")
    static let grailsCollection = UTType(exportedAs: "\(grailsAppID).collection")
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case like, note, move, tag, copyURL, shuffle, trash
    case commandPalette, zoomIn, zoomOut, newCollection, newSmartFolder
    var id: String { rawValue }

    var title: String {
        switch self {
        case .like: "Like / unlike"
        case .note: "Add or edit note"
        case .move: "Move to collection"
        case .tag: "Edit tags"
        case .copyURL: "Copy source URL"
        case .shuffle: "Shuffle"
        case .trash: "Move to Trash"
        case .commandPalette: "Command palette"
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .newCollection: "New collection"
        case .newSmartFolder: "New smart folder"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .like: Shortcut("l")
        case .note: Shortcut("n")
        case .move: Shortcut("m")
        case .tag: Shortcut("t")
        case .copyURL: Shortcut("u")
        case .shuffle: Shortcut("r")
        case .trash: Shortcut("delete")
        case .commandPalette: Shortcut("k", [.command])
        case .zoomIn: Shortcut("=", [.command])
        case .zoomOut: Shortcut("-", [.command])
        case .newCollection: Shortcut("n", [.command, .shift])
        case .newSmartFolder: Shortcut("n", [.command, .option])
        }
    }
}

enum ShortcutConflict: Equatable {
    case reserved(String)
    case fixed(String)
    case action(ShortcutAction)

    var message: String {
        switch self {
        case .reserved(let why): "That shortcut is reserved: \(why)"
        case .fixed(let why): why
        case .action(let a): "Already used by “\(a.title)”"
        }
    }
}

/// Rebindable shortcuts. Defaults live in `ShortcutAction`; only changes are persisted.
@MainActor @Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    private let defaultsKey = "shortcutOverrides"
    private(set) var overrides: [String: Shortcut] = [:]

    /// Standard Mac commands people expect to keep working.
    static let reserved: [String: String] = [
        "⌘Q": "Quit", "⌘W": "Close window", "⌘H": "Hide", "⌥⌘H": "Hide others", "⌘M": "Minimize", "⌘,": "Settings",
        "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘A": "Select all", "⌘Z": "Undo", "⇧⌘Z": "Redo", "⌘O": "Open library",
        "⌘F": "Search", "⌘1": "Grid view", "⌘2": "Canvas view", "⌘3": "Infinity view", "⌘`": "Switch window",
    ]
    /// Keys the app uses with fixed meaning when nothing is modified.
    static let fixedPlain: [String: String] = [
        "space": "Space opens the preview", "return": "Return opens the preview", "escape": "Escape clears the selection",
        "tab": "Tab moves focus", "left": "Arrow keys move the selection", "right": "Arrow keys move the selection",
        "up": "Arrow keys move the selection", "down": "Arrow keys move the selection",
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Shortcut].self, from: data) { overrides = decoded }
    }

    func shortcut(for a: ShortcutAction) -> Shortcut { overrides[a.rawValue] ?? a.defaultShortcut }
    func isCustomized(_ a: ShortcutAction) -> Bool { overrides[a.rawValue] != nil }

    func action(for event: NSEvent, plainOnly: Bool) -> ShortcutAction? {
        guard let s = Shortcut(event: event) else { return nil }
        return ShortcutAction.allCases.first { a in
            let sc = shortcut(for: a)
            return sc == s && (!plainOnly || sc.isPlain)
        }
    }

    func conflict(for s: Shortcut, action: ShortcutAction) -> ShortcutConflict? {
        if s.isPlain, let why = Self.fixedPlain[s.key] { return .fixed(why) }
        if let why = Self.reserved[s.display] { return .reserved(why) }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcut(for: $0) == s }) { return .action(other) }
        return nil
    }

    /// Returns the conflict when the binding is refused.
    @discardableResult
    func set(_ s: Shortcut, for a: ShortcutAction) -> ShortcutConflict? {
        if let c = conflict(for: s, action: a) { return c }
        if s == a.defaultShortcut { overrides[a.rawValue] = nil } else { overrides[a.rawValue] = s }
        persist()
        return nil
    }

    func reset(_ a: ShortcutAction) { overrides[a.rawValue] = nil; persist() }
    func resetAll() { overrides = [:]; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}
