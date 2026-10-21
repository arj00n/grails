import Foundation

/// What a keychain read actually returned. Anything other than "not there" must not be treated as an empty vault.
public enum KeychainOutcome: Equatable, Sendable {
    case value(Data)
    case missing
    case failed(Int32)
}

/// A listing of every account under the service. A failed listing is not an empty vault.
public enum KeychainListing: Equatable, Sendable {
    case items([String: Data])
    case missing
    case failed(Int32)
}

public enum KeychainLoadDecision: Equatable, Sendable {
    /// The session may be used. `persist` folds legacy accounts into the one bundle item.
    case ready(SecretBundle, persist: Bool)
    case blocked
}

public enum KeychainStorePlan: Equatable, Sendable {
    case updated
    case add
    case failed(Int32)
}

/// Decides whether a keychain read may become the session, and how a later write updates the item.
/// A denied prompt, a locked keychain, or any other error blocks writes. Only a real "not found" is an empty vault.
public enum KeychainPolicy {
    public static let success: Int32 = 0
    /// `errSecItemNotFound`.
    public static let notFound: Int32 = -25300

    public static func load(bundle: KeychainOutcome, listing: KeychainListing) -> KeychainLoadDecision {
        switch bundle {
        case .failed:
            return .blocked
        case .value(let data):
            guard let decoded = try? JSONDecoder().decode(SecretBundle.self, from: data) else { return .blocked }
            return .ready(decoded, persist: false)
        case .missing:
            switch listing {
            case .failed:
                return .blocked
            case .missing:
                return .ready(SecretBundle(), persist: false)
            case .items(let items):
                let absorbed = SecretAccounts.absorb(items)
                return .ready(absorbed.bundle, persist: !absorbed.legacy.isEmpty)
            }
        }
    }

    /// Update in place. Add only when the item is not there yet. Never delete first.
    public static func store(updateStatus: Int32) -> KeychainStorePlan {
        if updateStatus == success { return .updated }
        if updateStatus == notFound { return .add }
        return .failed(updateStatus)
    }
}
