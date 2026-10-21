import Foundation

/// When the sidebar should say sync is in trouble. One short failure stays quiet. Three in a row, or one pass that runs at least two minutes, stays up until a pass succeeds. Offline and a cancelled pass do not count.
public struct SyncHealth: Equatable, Sendable {
    public var streak: Int
    public var showing: Bool

    public static let consecutiveLimit = 3
    public static let longFailure: TimeInterval = 120
    public static let clean = SyncHealth(streak: 0, showing: false)

    public enum Outcome: Equatable, Sendable {
        case success
        case failed(TimeInterval)
        case cancelled
        case offline
    }

    public enum Banner: Equatable, Sendable {
        case disconnected
        case failing
        case offline

        public var label: String {
            switch self {
            case .disconnected: "Disconnected"
            case .failing: "Sync failing"
            case .offline: "Offline"
            }
        }
    }

    public func next(_ outcome: Outcome) -> SyncHealth {
        switch outcome {
        case .success:
            return .clean
        case .cancelled, .offline:
            return self
        case .failed(let duration):
            let streak = streak + 1
            let trip = streak >= Self.consecutiveLimit || duration >= Self.longFailure
            return SyncHealth(streak: streak, showing: showing || trip)
        }
    }

    /// Offline wins over a latched failure, so a Mac with no network does not look like a broken sync. A library that does not sync stays quiet.
    public static func banner(revoked: Bool, connected: Bool, shared: Bool, reachable: Bool, health: SyncHealth) -> Banner? {
        if revoked || (shared && !connected) { return .disconnected }
        if !reachable, connected || shared { return .offline }
        if health.showing { return .failing }
        return nil
    }
}

/// What a sleep or a network change should do to the in-flight pass. The app turns these into `NSWorkspace` and `NWPathMonitor` events.
public enum SyncInterrupt {
    public enum Event: Equatable, Sendable {
        case willSleep
        case didWake
        case pathUnsatisfied
        case pathSatisfied
    }

    public struct Response: Equatable, Sendable {
        public var cancel: Bool
        public var fresh: Bool
        public var reachable: Bool?

        public init(cancel: Bool, fresh: Bool, reachable: Bool?) {
            self.cancel = cancel
            self.fresh = fresh
            self.reachable = reachable
        }
    }

    public static func response(_ event: Event) -> Response {
        switch event {
        case .willSleep:
            return Response(cancel: true, fresh: false, reachable: nil)
        case .didWake:
            return Response(cancel: true, fresh: true, reachable: nil)
        case .pathUnsatisfied:
            return Response(cancel: true, fresh: false, reachable: false)
        case .pathSatisfied:
            return Response(cancel: true, fresh: true, reachable: true)
        }
    }
}

public enum SyncStep: String, Sendable, Equatable {
    case list, get, put, roster, sync
}

/// A transfer that received no request or response bytes for `HTTPTimeouts.stall`. Distinct from a task cancelled because the Mac slept.
public struct TransferStall: Error, Equatable {}

public enum SyncFailureLog {
    public static func line(step: SyncStep, error: Error, milliseconds: Int) -> String {
        let (domain, code, reason) = describe(error)
        return "poll failed step=\(step.rawValue) ms=\(milliseconds) domain=\(domain) code=\(code) reason=\(sanitize(reason))"
    }

    static func describe(_ error: Error) -> (String, String, String) {
        if error is TransferStall { return ("TransferStall", "0", "stalled") }
        if let s3 = error as? S3Error {
            switch s3 {
            case .preconditionFailed: return ("S3Error", "412", "precondition failed")
            case .notFound: return ("S3Error", "404", "not found")
            case .badResponse: return ("S3Error", "badResponse", "bad response")
            case .status(let code, let body): return ("S3Error", String(code), body.isEmpty ? "status \(code)" : body)
            }
        }
        if let failure = error as? SyncFailure {
            switch failure {
            case .notAllowed: return ("SyncFailure", "notAllowed", "not allowed")
            case .blocked: return ("SyncFailure", "blocked", "update required")
            case .revoked: return ("SyncFailure", "revoked", "revoked")
            }
        }
        let ns = error as NSError
        return (ns.domain, String(ns.code), ns.localizedDescription)
    }

    /// Drops URLs and signature material. A signed request URL must not land in the log.
    static func sanitize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        text = redactURLs(text)
        for marker in ["X-Amz-Signature=", "X-Amz-Credential=", "AWSAccessKeyId=", "X-Amz-Security-Token="] {
            text = redact(marker: marker, in: text)
        }
        if text.count > 180 { text = String(text.prefix(180)) }
        return text
    }

    private static func redactURLs(_ raw: String) -> String {
        var out = ""
        var rest = raw[...]
        while let scheme = rest.range(of: "https://") ?? rest.range(of: "http://") {
            out += rest[..<scheme.lowerBound]
            out += "[url]"
            var index = scheme.upperBound
            while index < rest.endIndex, !rest[index].isWhitespace, rest[index] != "\"" {
                index = rest.index(after: index)
            }
            rest = rest[index...]
        }
        out += rest
        return out
    }

    private static func redact(marker: String, in raw: String) -> String {
        var out = ""
        var rest = raw[...]
        while let range = rest.range(of: marker) {
            out += rest[..<range.upperBound]
            out += "[redacted]"
            var index = range.upperBound
            while index < rest.endIndex, rest[index] != "&", rest[index] != " ", rest[index] != "\"" {
                index = rest.index(after: index)
            }
            rest = rest[index...]
        }
        out += rest
        return out
    }
}
