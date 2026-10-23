import Foundation

public enum ExtensionNudgeBrowser: Equatable, Sendable {
    case chromium, safari, other
}

public enum ExtensionNudgeAction: Equatable, Sendable {
    case addToChrome
    case enableInSafari
}

public struct ExtensionNudgeOffer: Equatable, Sendable {
    public var primary: ExtensionNudgeAction
    public var secondary: ExtensionNudgeAction?
    /// Both actions carry the same weight. The default browser was not one of them.
    public var compact: Bool

    public init(primary: ExtensionNudgeAction, secondary: ExtensionNudgeAction?, compact: Bool) {
        self.primary = primary
        self.secondary = secondary
        self.compact = compact
    }
}

/// What the sidebar card remembers. A Chrome pair hides it for good. A Safari pair hides it only while Safari ships in this build.
public struct ExtensionNudgeRecord: Codable, Equatable, Sendable {
    public static let snoozeInterval: TimeInterval = 3 * 24 * 60 * 60
    public static let defaultsKey = "extensionNudge.v1"

    public var chromePaired: Bool
    public var safariPaired: Bool
    public var snoozeUntil: Date?

    public init(chromePaired: Bool = false, safariPaired: Bool = false, snoozeUntil: Date? = nil) {
        self.chromePaired = chromePaired
        self.safariPaired = safariPaired
        self.snoozeUntil = snoozeUntil
    }

    public static func load(_ defaults: UserDefaults = .standard) -> ExtensionNudgeRecord {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(ExtensionNudgeRecord.self, from: $0) } ?? ExtensionNudgeRecord()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// Keeps each origin. `offer` applies the Safari switch, so a pair stored while Safari is off still counts once it is on.
    public mutating func note(_ origin: PairingOrigin) {
        switch origin {
        case .chromeStore: chromePaired = true
        case .safari: safariPaired = true
        }
    }

    public mutating func snooze(now: Date) {
        snoozeUntil = now.addingTimeInterval(Self.snoozeInterval)
    }

    public func offer(safariAvailable: Bool, browser: ExtensionNudgeBrowser, safariEnabled: Bool, now: Date) -> ExtensionNudgeOffer? {
        if chromePaired { return nil }
        if safariAvailable, safariPaired || safariEnabled { return nil }
        if let snoozeUntil, now < snoozeUntil { return nil }
        guard safariAvailable else {
            return ExtensionNudgeOffer(primary: .addToChrome, secondary: nil, compact: false)
        }
        switch browser {
        case .safari:
            return ExtensionNudgeOffer(primary: .enableInSafari, secondary: .addToChrome, compact: false)
        case .chromium:
            return ExtensionNudgeOffer(primary: .addToChrome, secondary: .enableInSafari, compact: false)
        case .other:
            return ExtensionNudgeOffer(primary: .addToChrome, secondary: .enableInSafari, compact: true)
        }
    }
}
