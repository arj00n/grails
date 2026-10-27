import Foundation

/// Lifetime comparison shared by the sheet, the session, and the allowance.
/// Matches `PairingBroker.state(of:)`: age >= `PairingBroker.lifetime` is expired.
private enum PairingClock {
    static func expired(created: Date, now: Date) -> Bool {
        now.timeIntervalSince(created) >= PairingBroker.lifetime
    }

    static func remaining(created: Date, now: Date) -> TimeInterval {
        max(0, PairingBroker.lifetime - now.timeIntervalSince(created))
    }
}

/// The one modal the app can show for a broker request.
/// Nil when the origin does not parse or the request has reached its lifetime.
public struct PairingSheetItem: Equatable, Sendable, Identifiable {
    public struct Copy: Equatable, Sendable {
        public let title: String
        public let line: String

        fileprivate init(title: String, line: String) {
            self.title = title
            self.line = line
        }
    }

    /// Minted only by `allowAnswer`, and only while the request is inside the lifetime.
    public struct Allowance: Equatable, Sendable {
        public let id: String
        public let origin: String
        public let created: Date

        fileprivate init(id: String, origin: String, created: Date) {
            self.id = id
            self.origin = origin
            self.created = created
        }

        public func isExpired(now: Date) -> Bool {
            PairingClock.expired(created: created, now: now)
        }
    }

    /// Minted only by `denyAnswer`, and only while the request is inside the lifetime.
    public struct Refusal: Equatable, Sendable {
        public let id: String
        fileprivate init(id: String) { self.id = id }
    }

    public enum AllowAnswer: Equatable, Sendable {
        case allow(Allowance)
        case expired(String)
    }

    public enum DenyAnswer: Equatable, Sendable {
        case deny(Refusal)
        case expired(String)
    }

    public let id: String
    public let copy: Copy
    private let origin: String
    private let created: Date

    public init?(_ request: PairingBroker.Request, now: Date) {
        guard let parsed = PairingOrigin.parse(request.origin) else { return nil }
        guard !PairingClock.expired(created: request.created, now: now) else { return nil }
        id = request.id
        origin = request.origin
        created = request.created
        copy = Copy(parsed)
    }

    public func expired(now: Date) -> Bool {
        PairingClock.expired(created: created, now: now)
    }

    /// Seconds until the lifetime. 0 when expired. The view sleeps this long.
    public func remaining(now: Date) -> TimeInterval {
        PairingClock.remaining(created: created, now: now)
    }

    public func allowAnswer(now: Date) -> AllowAnswer {
        if expired(now: now) { return .expired(id) }
        return .allow(Allowance(id: id, origin: origin, created: created))
    }

    public func denyAnswer(now: Date) -> DenyAnswer {
        if expired(now: now) { return .expired(id) }
        return .deny(Refusal(id: id))
    }
}

extension PairingSheetItem.Copy {
    init(_ origin: PairingOrigin) {
        let line = "Save to Grails is asking to connect to this Mac."
        switch origin {
        case .chromeStore:
            self.init(title: "Connect Chrome?", line: line)
        case .safari:
            self.init(title: "Connect Safari?", line: line)
        }
    }
}

/// Once-per-id activation ledger. Does not store the request. `pairRequest` remains the shown value.
public struct PairingSession: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        /// Restore the window, then assign `pairRequest`.
        case showInFront(PairingBroker.Request)
        /// Assign `pairRequest`. This id already took the front.
        case show(PairingBroker.Request)
        /// If this id is showing, clear it. Do not approve and do not deny.
        case clear(String)
    }

    private var broughtToFront: String?

    public init() {}

    public mutating func deliver(_ request: PairingBroker.Request, now: Date) -> Delivery {
        guard PairingSheetItem(request, now: now) != nil else { return .clear(request.id) }
        if broughtToFront == request.id { return .show(request) }
        broughtToFront = request.id
        return .showInFront(request)
    }
}
