import Foundation

/// One pin as the browser extension saw it on the page: its id and the picture it was showing.
public struct ExtensionPin: Codable, Sendable, Equatable {
    public var id: String
    public var image: String?
    public init(id: String, image: String? = nil) { self.id = id; self.image = image }
}

/// A board the extension scrolled: its pins, as they appeared.
public struct ExtensionBoard: Codable, Sendable, Equatable {
    public var url: String
    public var name: String?
    public var pins: [ExtensionPin]
    public init(url: String, name: String? = nil, pins: [ExtensionPin]) { self.url = url; self.name = name; self.pins = pins }
}

/// A board found on a profile page (the extension lists them; the person picks).
public struct ListedBoard: Codable, Sendable, Equatable {
    public var url: String
    public var name: String
    public var count: Int?
    public var cover: String?
    public init(url: String, name: String, count: Int? = nil, cover: String? = nil) { self.url = url; self.name = name; self.count = count; self.cover = cover }
}

/// "Chrome wants in": a browser extension asks to be paired, and nothing happens until the person clicks Allow in the app.
public final class PairingBroker: @unchecked Sendable {
    public enum State: Sendable, Equatable { case pending, approved, denied }
    public struct Request: Sendable, Equatable { public var id: String; public var origin: String; public var created: Date; public var state: State }

    public static let lifetime: TimeInterval = 120
    private let lock = NSLock()
    private var requests: [String: Request] = [:]
    /// The app shows an Allow prompt when this fires.
    public var onRequest: (@Sendable (Request) -> Void)?

    public init() {}

    /// Opens a request, or nil when another is still waiting for an answer.
    public func open(origin: String, now: Date = Date()) -> String? {
        lock.lock()
        if requests.values.contains(where: { $0.state == .pending && now.timeIntervalSince($0.created) < Self.lifetime }) { lock.unlock(); return nil }
        let r = Request(id: UUID().uuidString, origin: origin, created: now, state: .pending)
        requests[r.id] = r
        let notify = onRequest
        lock.unlock()
        notify?(r)
        return r.id
    }

    public func state(of id: String, now: Date = Date()) -> State? {
        lock.lock(); defer { lock.unlock() }
        guard let r = requests[id] else { return nil }
        if r.state == .pending, now.timeIntervalSince(r.created) >= Self.lifetime { return .denied }
        return r.state
    }

    public func approve(_ id: String) { set(id, .approved) }
    public func deny(_ id: String) { set(id, .denied) }

    public var pending: Request? {
        lock.lock(); defer { lock.unlock() }
        return requests.values.first { $0.state == .pending && Date().timeIntervalSince($0.created) < Self.lifetime }
    }

    private func set(_ id: String, _ s: State) {
        lock.lock(); requests[id]?.state = s; lock.unlock()
    }
}

/// Work the app hands to the extension: list the boards on a profile, or scroll these boards. The extension finds it by nonce
/// (the app opens the browser at `…#grails=<nonce>`), and reports back through the callbacks.
public final class ExtensionJobs: @unchecked Sendable {
    public enum Kind: Codable, Sendable, Equatable { case list(profile: String), collect(boards: [String]) }
    public struct Spec: Codable, Sendable, Equatable { public var nonce: String; public var kind: String; public var profile: String?; public var boards: [String]? }

    private let lock = NSLock()
    private var jobs: [String: Kind] = [:]
    public var onBoards: (@Sendable (String, [ListedBoard]) -> Void)?
    public var onProgress: (@Sendable (String, String, Int) -> Void)?
    public var onDone: (@Sendable (String) -> Void)?

    public init() {}

    public func create(_ kind: Kind) -> String {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        lock.lock(); jobs[nonce] = kind; lock.unlock()
        return nonce
    }

    public func spec(_ nonce: String) -> Spec? {
        lock.lock(); defer { lock.unlock() }
        switch jobs[nonce] {
        case .list(let profile)?: return Spec(nonce: nonce, kind: "list", profile: profile, boards: nil)
        case .collect(let boards)?: return Spec(nonce: nonce, kind: "collect", profile: nil, boards: boards)
        case nil: return nil
        }
    }

    public func finish(_ nonce: String) { lock.lock(); jobs[nonce] = nil; lock.unlock() }
}
