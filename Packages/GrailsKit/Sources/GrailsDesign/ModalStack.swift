import Foundation

/// The one rule for modals: a modal opens above whatever presented it. Each modal hangs from a window, or from the modal on top of
/// that window, so a modal opened from a page (the library, Settings) sits on its window and one opened from a modal sits on that
/// modal. The topmost one takes focus and Esc. Closing a modal closes the ones stacked on it first. `GrailsModalLayer` keeps one of these for the app.
public struct ModalStack<Window: Hashable>: Equatable {
    public enum Parent: Hashable {
        /// A window that is not a modal: the main window, whichever page it shows.
        case window(Window)
        /// Another modal, by id.
        case modal(String)
    }

    public struct Entry: Hashable {
        public let id: String
        public let parent: Parent
        /// The window the chain starts from.
        public let root: Window
    }

    /// Bottom to top, in the order they opened.
    public private(set) var entries: [Entry] = []

    public init() {}

    public func contains(_ id: String) -> Bool { entries.contains { $0.id == id } }

    /// The modal that has focus and gets Esc.
    public var top: String? { entries.last?.id }

    public func isTopmost(_ id: String) -> Bool { top == id }

    /// Nothing is stacked on `id` over its own window, so Esc there is its.
    public func isTopOfItsWindow(_ id: String) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        return topmost(over: entry.root)?.id == id
    }

    /// Where a modal asked for from `presenter` attaches: the topmost modal already over that window, else the window.
    /// `presenter` may itself be a modal's window: pass its id as `presenterModal`.
    public func parent(presenter: Window, presenterModal: String? = nil) -> Parent {
        if let presenterModal, let entry = entries.first(where: { $0.id == presenterModal }) {
            return .modal(topmost(over: entry.root)?.id ?? entry.id)
        }
        if let over = topmost(over: presenter) { return .modal(over.id) }
        return .window(presenter)
    }

    /// Opens `id` above `presenter`. Opening one that is already open leaves the stack as it is.
    @discardableResult
    public mutating func push(_ id: String, presenter: Window, presenterModal: String? = nil) -> Parent {
        if let open = entries.first(where: { $0.id == id }) { return open.parent }
        let parent = parent(presenter: presenter, presenterModal: presenterModal)
        let root: Window = switch parent {
        case .window(let w): w
        case .modal(let m): entries.first { $0.id == m }?.root ?? presenter
        }
        entries.append(Entry(id: id, parent: parent, root: root))
        return parent
    }

    /// Closes `id` and everything stacked on it. Returns the ids to close, topmost first.
    @discardableResult
    public mutating func remove(_ id: String) -> [String] {
        guard entries.contains(where: { $0.id == id }) else { return [] }
        var closing: Set<String> = [id]
        // children open after their parent, so one pass in order finds every descendant
        for e in entries { if case .modal(let p) = e.parent, closing.contains(p) { closing.insert(e.id) } }
        let order = entries.filter { closing.contains($0.id) }.map(\.id).reversed()
        entries.removeAll { closing.contains($0.id) }
        return Array(order)
    }

    /// Where focus goes once `id` closes: the modal it hung from, or its window.
    public func focusAfterClosing(_ id: String) -> Parent? {
        entries.first { $0.id == id }?.parent
    }

    /// The topmost modal whose chain starts at `window`.
    public func topmost(over window: Window) -> Entry? {
        entries.last { $0.root == window }
    }
}
