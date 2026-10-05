import Foundation

/// A `grails://open?...` (links made before the rename, `stash://`, still open) link to a library, a collection, a tag or one item. It carries the library's id (not a path), so it
/// works on every Mac that has that library, wherever its synced folder lives.
public struct GrailsLink: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case library
        case collection(String)
        case tag(String)
        case item(String)
    }

    public var library: String
    /// The library's name, so a Mac that hasn't added it yet can say which one this is.
    public var name: String?
    public var target: Target
    /// Open the canvas rather than the grid.
    public var canvas: Bool
    /// Where the library lives (invite links only), so a Mac that can't find it can say what's missing. Older links don't have it.
    public var hint: LibraryHint?

    public init(library: String, name: String? = nil, target: Target = .library, canvas: Bool = false, hint: LibraryHint? = nil) {
        self.library = library; self.name = name; self.target = target; self.canvas = canvas; self.hint = hint
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = "grails"
        c.host = "open"
        var q = [URLQueryItem(name: "lib", value: library)]
        if let name, !name.isEmpty { q.append(URLQueryItem(name: "name", value: name)) }
        switch target {
        case .library: break
        case .collection(let id): q.append(URLQueryItem(name: "c", value: id))
        case .tag(let tag): q.append(URLQueryItem(name: "t", value: tag))
        case .item(let id): q.append(URLQueryItem(name: "i", value: id))
        }
        if canvas { q.append(URLQueryItem(name: "v", value: "canvas")) }
        if let hint { q += hint.queryItems }
        c.queryItems = q
        return c.url ?? URL(string: "grails://open")!
    }

    /// The same link as a web address on a page you host (`docs/router/index.html`): the details ride in the `#` part, so the
    /// host never sees them, and the page hands them to the app. Chat apps make these clickable; they don't for `grails://`.
    public func webURL(page: URL) -> URL {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        return URL(string: page.absoluteString.split(separator: "#").first.map(String.init)! + "#" + query) ?? page
    }

    public init?(url: URL) {
        // a router-page address: take the details from after the #
        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let fragment = url.fragment, !fragment.isEmpty,
           let inner = URL(string: "grails://open?" + fragment), let link = GrailsLink(url: inner) {
            self = link
            return
        }
        guard ["grails", "stash"].contains(url.scheme?.lowercased() ?? ""), url.host?.lowercased() == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ k: String) -> String? { items.first { $0.name == k }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        guard let lib = value("lib") else { return nil }
        library = lib
        name = value("name")
        canvas = value("v") == "canvas"
        hint = LibraryHint(items: items)
        if let c = value("c") { target = .collection(c) }
        else if let t = value("t") { target = .tag(t) }
        else if let i = value("i") { target = .item(i) }
        else { target = .library }
    }

    /// Accepts a pasted link, with or without stray whitespace.
    public init?(text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let l = GrailsLink(url: url) else { return nil }
        self = l
    }
}
