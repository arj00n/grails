import Foundation

/// The team library set-up, as a pure state machine: where the team keeps files → the folder → check → share → invite → done.
public struct CollabSetupFlow: Equatable, Sendable {
    public enum Step: String, Codable, Sendable, CaseIterable {
        case service, place, check, share, invite, done

        /// The step strip's labels.
        public var label: String {
            switch self {
            case .service: "Where"
            case .place: "Folder"
            case .check: "Check"
            case .share: "Share"
            case .invite: "Invite"
            case .done: "Done"
            }
        }
    }

    public enum Event: Equatable, Sendable {
        /// A service (and account) was picked on the first screen.
        case choseService
        /// The library exists in the chosen folder (made or picked).
        case libraryReady
        /// Continue on Check: allowed only when nothing blocks.
        case checked(canContinue: Bool)
        case shared
        case invited
        case back
        /// Pick a different folder (from Check, when the place is wrong).
        case changeFolder
    }

    public private(set) var step: Step

    /// A library already in a synced folder starts at Check (nothing to make); anything else starts at the beginning.
    public init(current: Placement?) {
        if let p = current, p.isSynced, p.kind != .driveTop, !p.inTrash { step = .check } else { step = .service }
    }

    public init(step: Step) { self.step = step }

    public mutating func send(_ event: Event) {
        switch (step, event) {
        case (.service, .choseService): step = .place
        case (.place, .libraryReady): step = .check
        case (.check, .checked(let ok)) where ok: step = .share
        case (.check, .changeFolder): step = .place
        case (.share, .shared): step = .invite
        case (.invite, .invited): step = .done
        case (.place, .back): step = .service
        case (.check, .back): step = .place
        case (.share, .back): step = .check
        case (.invite, .back): step = .share
        case (.done, .back): step = .invite
        default: break
        }
    }

    /// Steps shown in the strip (Done isn't one).
    public static let strip: [Step] = [.service, .place, .check, .share, .invite]
}
