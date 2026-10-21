import Foundation

/// A page of Settings, in the order the section list shows them.
public enum SettingsSection: String, CaseIterable, Sendable {
    case general, library, shortcuts, extensions, team, storage

    /// A stored or launch-time name. `appearance` was the General tab's old name.
    public init?(name: String) {
        if name == "appearance" { self = .general; return }
        self.init(rawValue: name)
    }
}

/// Settings is a page of the main window, not a window of its own. It covers the library while it is open and gives the
/// window back as it was when it closes. Re-opening it returns to the section it was on.
public struct SettingsNavigation: Equatable, Sendable {
    public private(set) var isOpen = false
    public private(set) var section: SettingsSection

    public init(section: SettingsSection = .general) {
        self.section = section
    }

    /// ⌘,, the sidebar gear, or ⌘K. Without a section it keeps the last one.
    public mutating func open(_ section: SettingsSection? = nil) {
        if let section { self.section = section }
        isOpen = true
    }

    /// The back control or ⌘[. False when it was already closed.
    @discardableResult
    public mutating func close() -> Bool {
        guard isOpen else { return false }
        isOpen = false
        return true
    }

    public mutating func select(_ section: SettingsSection) {
        self.section = section
    }

    /// Esc. A modal on top takes Esc itself, so Settings closes only when nothing is open over it.
    @discardableResult
    public mutating func escape(modalOpen: Bool) -> Bool {
        guard !modalOpen else { return false }
        return close()
    }

    /// The sections the list shows. Team shows once the library is shared, Storage to whoever sees the bucket controls. The
    /// open section always shows, so a launch straight into Team or Storage, or a disconnect while there, keeps its row.
    public func visibleSections(teamConnected: Bool, seesStorage: Bool) -> [SettingsSection] {
        SettingsSection.allCases.filter { s in
            switch s {
            case .team: teamConnected || section == .team || section == .storage
            case .storage: seesStorage || section == .storage
            default: true
            }
        }
    }
}
