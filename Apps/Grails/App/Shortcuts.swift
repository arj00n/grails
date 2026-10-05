import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let grailsItems = UTType(exportedAs: "xyz.arjoon.grails.items")
    static let grailsCollection = UTType(exportedAs: "xyz.arjoon.grails.collection")
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case toggleInfo, like, note, move, tag, copyURL, shuffle, trash
    case commandPalette, zoomIn, zoomOut, newCollection, newSmartFolder
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleInfo: "Show or hide info panel"
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
        case .toggleInfo: Shortcut("i")
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

struct Shortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt

    init(_ key: String, _ mods: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = mods.intersection(Self.mask).rawValue
    }

    static let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    /// Plain keys are handled by the grid (so they never fire while typing); modified ones become menu key equivalents.
    var isPlain: Bool { flags.isEmpty }

    init?(event: NSEvent) {
        guard let key = Self.keyName(for: event) else { return nil }
        self.init(key, event.modifierFlags)
    }

    static func keyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 51, 117: return "delete"
        case 36, 76: return "return"
        case 49: return "space"
        case 53: return "escape"
        case 48: return "tab"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default: break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first, !ch.isNewline else { return nil }
        return String(ch)
    }

    var display: String {
        var s = ""
        let f = flags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        switch key {
        case "delete": s += "⌫"
        case "return": s += "↩"
        case "space": s += "Space"
        case "escape": s += "⎋"
        case "tab": s += "⇥"
        case "left": s += "←"
        case "right": s += "→"
        case "up": s += "↑"
        case "down": s += "↓"
        default: s += key.uppercased()
        }
        return s
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "delete": .delete
        case "return": .return
        case "space": .space
        case "escape": .escape
        case "tab": .tab
        case "left": .leftArrow
        case "right": .rightArrow
        case "up": .upArrow
        case "down": .downArrow
        default: key.count == 1 ? KeyEquivalent(Character(key)) : nil
        }
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.control) { m.insert(.control) }
        return m
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

extension View {
    /// Menu key equivalent for modified shortcuts; plain-key shortcuts are intentionally not menu equivalents.
    @MainActor @ViewBuilder
    func shortcut(_ action: ShortcutAction, _ store: ShortcutStore = .shared) -> some View {
        let s = store.shortcut(for: action)
        if !s.isPlain, let k = s.keyEquivalent { keyboardShortcut(k, modifiers: s.eventModifiers) } else { self }
    }
}
