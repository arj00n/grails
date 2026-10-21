import Foundation

public enum DisplayName {
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Save is offered only when the draft is a real name and it differs from the current one.
    public static func canSave(draft: String, current: String) -> Bool {
        guard let name = normalized(draft) else { return false }
        return name != current
    }
}

public enum TeammateStep: Equatable, Sendable {
    case link
    case code
    case name
    case blocked
    case done

    public var id: String {
        switch self {
        case .link: "link"
        case .code: "code"
        case .name: "name"
        case .blocked: "blocked"
        case .done: "done"
        }
    }
}

public enum TeammateJoinResult: Equatable, Sendable {
    case joined
    case failed(TeammateJoinError)
    case inProgress
}

public enum TeammateJoinError: Equatable, Sendable {
    case badCode
    case expired
    case alreadyUsed
    case outdated(minAppVersion: String, appVersion: String)
    case locked
    case emailMismatch
    case malformed
}

public struct TeammateOnboarding: Equatable, Sendable {
    public static let stepCount = 3

    public private(set) var step: TeammateStep
    public private(set) var error: TeammateJoinError?
    public private(set) var link: JoinLink?
    public private(set) var code: String
    /// The email sealed in the invite. It is shown, not edited.
    public private(set) var invitedEmail: String
    public private(set) var displayName: String

    public init() {
        step = .link
        error = nil
        link = nil
        code = ""
        invitedEmail = ""
        displayName = ""
    }

    public var stepNumber: Int {
        switch step {
        case .link: 1
        case .code: 2
        case .name, .blocked, .done: 3
        }
    }

    public var title: String {
        switch step {
        case .link: "Invite link"
        case .code: "Join code"
        case .name: "Your name"
        case .blocked: "Update Grails"
        case .done: "Library"
        }
    }

    public var message: String? {
        switch error {
        case .badCode: "That code doesn't match. Check it and try again."
        case .expired: "This invite has expired. Ask for a new one."
        case .alreadyUsed: "This invite has already been used. Ask for a new one."
        case .outdated: "Update Grails"
        case .locked: "Too many wrong codes. Ask for a new invite."
        case .emailMismatch: "That email doesn't match the invite"
        case .malformed: "That link looks incomplete. Copy it again from the invite."
        case nil: nil
        }
    }

    public var canContinue: Bool {
        switch error {
        case .locked, .expired, .alreadyUsed, .outdated: return false
        case .badCode, .emailMismatch, .malformed, nil:
            if step == .blocked || step == .done { return false }
            if step == .name { return DisplayName.normalized(displayName) != nil }
            return true
        }
    }

    public mutating func submitLink(_ text: String) {
        guard step == .link else { return }
        error = nil
        guard let found = JoinLink.find(in: text), !found.blob.isEmpty else {
            error = .malformed
            return
        }
        link = found
        step = .code
    }

    public mutating func submitCode(_ raw: String) {
        guard step == .code else { return }
        error = nil
        guard let normalized = InviteCode.normalize(raw) else {
            error = .badCode
            return
        }
        code = normalized
        step = .name
    }

    /// The invite already names the email. The only thing left to ask is the display name.
    public mutating func noteInvite(email: String, suggestedName: String) {
        invitedEmail = TeamEmail.normalize(email)
        if DisplayName.normalized(displayName) == nil, let suggested = DisplayName.normalized(suggestedName) {
            displayName = suggested
        }
    }

    /// The field binding. A blank value stays blank so Continue can turn off.
    public mutating func editName(_ raw: String) {
        guard step == .name else { return }
        displayName = raw
    }

    @discardableResult
    public mutating func submitName(_ raw: String) -> Bool {
        guard step == .name else { return false }
        error = nil
        guard let name = DisplayName.normalized(raw) else { return false }
        displayName = name
        return true
    }

    public mutating func back() {
        error = nil
        switch step {
        case .code: step = .link
        case .name: step = .code
        case .link, .blocked, .done: break
        }
    }

    public mutating func fail(_ error: TeammateJoinError) {
        self.error = error
        switch error {
        case .badCode, .locked: step = .code
        case .malformed: step = .link
        case .expired, .alreadyUsed, .emailMismatch: step = .name
        case .outdated: step = .blocked
        }
    }

    public mutating func finish() {
        guard error == nil, step == .name, DisplayName.normalized(displayName) != nil else { return }
        step = .done
    }

    public static func error(from redeem: RedeemError) -> TeammateJoinError {
        switch redeem {
        case .wrongCode: .badCode
        case .locked: .locked
        case .expired: .expired
        case .alreadyRedeemed, .otherDevice: .alreadyUsed
        case .emailMismatch: .emailMismatch
        case .malformed: .malformed
        }
    }

    public static func formatGate(app: String, minimum: String?) -> TeammateJoinError? {
        guard let minimum, !AppVersion.allowsSync(app: app, minimum: minimum) else { return nil }
        return .outdated(minAppVersion: minimum, appVersion: app)
    }
}
