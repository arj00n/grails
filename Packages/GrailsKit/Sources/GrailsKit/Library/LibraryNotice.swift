import Foundation

/// The toast for liking, unliking, or a Holy Grail change. One notice per action, shared by the rosette, the heart,
/// the item menu, the command palette and the shortcuts. The screen draws it with `GrailsToast`; this only chooses the words and the mark.
public struct LibraryNotice: Equatable, Sendable {
    public enum Mark: Equatable, Sendable {
        case heart
        case heartSlash
        /// The filled gold rosette.
        case canon
        /// That same rosette with a slash cut through it.
        case canonStruck

        /// The SF Symbol for a heart. Holy Grail is `CanonMark`, not a symbol, so this is nil.
        public var symbolName: String? {
            switch self {
            case .heart: "heart"
            case .heartSlash: "heart.slash"
            case .canon, .canonStruck: nil
            }
        }

        /// Whether this is Holy Grail's mark, and whether the slash is cut through it.
        public var holyGrailStruck: Bool? {
            switch self {
            case .canon: false
            case .canonStruck: true
            case .heart, .heartSlash: nil
            }
        }
    }

    public var text: String
    public var mark: Mark

    public init(text: String, mark: Mark) {
        self.text = text
        self.mark = mark
    }

    /// `on` is the state just written: liked, or not.
    public static func like(on: Bool, count: Int) -> LibraryNotice {
        let word = on ? "Liked" : "Unliked"
        let text = count == 1 ? word : "\(word) \(count) items"
        return LibraryNotice(text: text, mark: on ? .heart : .heartSlash)
    }

    /// `added` is the state just written.
    public static func holyGrail(added: Bool, count: Int) -> LibraryNotice {
        let text: String
        if count == 1 {
            text = added ? "Added to \(Canon.title)" : "Removed from \(Canon.title)"
        } else {
            text = added ? "Added \(count) items to \(Canon.title)" : "Removed \(count) items from \(Canon.title)"
        }
        return LibraryNotice(text: text, mark: added ? .canon : .canonStruck)
    }
}
