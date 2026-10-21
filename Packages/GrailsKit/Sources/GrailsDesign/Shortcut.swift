import AppKit
import SwiftUI

public struct Shortcut: Codable, Hashable {
    public var key: String
    public var modifiers: UInt

    public init(_ key: String, _ mods: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = mods.intersection(Self.mask).rawValue
    }

    public static let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
    public var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    /// Plain keys stay with the grid and do not fire while typing. Modified keys are menu equivalents.
    public var isPlain: Bool { flags.isEmpty }

    public init?(event: NSEvent) {
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

    public var display: String {
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

    public var keyEquivalent: KeyEquivalent? {
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

    public var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }
}
