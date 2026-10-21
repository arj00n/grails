import Foundation

/// Something about where a team library sits that decides who gets it.
public enum PlacementIssue: Equatable, Sendable, Hashable {
    case local
    case trash
    case driveTop
    case otherComputers
    case myDrive
    case sharedWithMe
    case personalAccount(String)
    case notUploaded
    case uploadFailed(String)
    case onlineOnly

    public enum Severity: Int, Comparable, Sendable {
        case info, wait, warn, block
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public var severity: Severity {
        switch self {
        case .local, .trash, .driveTop: .block
        case .otherComputers, .myDrive, .personalAccount, .uploadFailed: .warn
        case .notUploaded: .wait
        case .sharedWithMe, .onlineOnly: .info
        }
    }

    public var title: String {
        switch self {
        case .local: "Only on this Mac"
        case .trash: "In the Trash"
        case .driveTop: "Not inside a drive"
        case .otherComputers: "In a computer backup"
        case .myDrive: "In My Drive"
        case .sharedWithMe: "In someone else's folder"
        case .personalAccount: "In a personal account"
        case .notUploaded: "Not uploaded yet"
        case .uploadFailed: "Drive couldn't upload it"
        case .onlineOnly: "Not on this Mac"
        }
    }

    /// One line, said plainly.
    public var detail: String {
        switch self {
        case .local: "No one else can reach this folder. Put the library in a Shared drive."
        case .trash: "Drive doesn't share what's in the Trash. Pick another folder."
        case .driveTop: "Pick a Shared drive, or a folder in My Drive."
        case .otherComputers: "Other computers is a backup of one Mac. Use a Shared drive."
        case .myDrive: "Only people you share the folder with get it, and each adds it to their Drive. A Shared drive gives everyone the same folder."
        case .sharedWithMe: "Its owner decides who gets it."
        case .personalAccount(let email): "It's in \(email). Your team probably uses your work account."
        case .notUploaded: "Drive hasn't taken it yet. Keep Drive running; this updates by itself."
        case .uploadFailed(let why): why
        case .onlineOnly: "Its files download when opened. Teammates still get it."
        }
    }
}

/// One line of the Check screen.
public struct PlacementCheckRow: Equatable, Sendable {
    public enum State: Equatable, Sendable { case ok, waiting, failed, unknown }
    public var label: String
    public var state: State
}

/// Everything the Check screen shows for a library folder.
public struct PlacementReport: Equatable, Sendable {
    public var placement: Placement
    public var rows: [PlacementCheckRow]
    public var issues: [PlacementIssue]

    /// Teammates can get it (nothing blocks); warnings are shown but don't stop the flow.
    public var canContinue: Bool { !issues.contains { $0.severity == .block } }
    /// Something is still on its way (Drive uploading): worth checking again by itself.
    public var waiting: Bool { issues.contains { $0.severity == .wait } }

    /// `waitedLong`: the Check screen has waited a while with no word from Drive (no id, no upload status). Then it stops promising and
    /// says it can't tell, since a Drive version that doesn't write the id would otherwise wait for ever.
    public init(placement: Placement, facts: FileFacts, accounts: [DriveAccount] = [], waitedLong: Bool = false) {
        self.placement = placement
        var issues: [PlacementIssue] = []
        if placement.inTrash { issues.append(.trash) }
        switch placement.kind {
        case .local: issues.append(.local)
        case .driveTop: issues.append(.driveTop)
        case .otherComputers: issues.append(.otherComputers)
        case .myDrive: issues.append(.myDrive)
        case .sharedWithMe: issues.append(.sharedWithMe)
        case .sharedDrive, .cloud: break
        }
        if let email = placement.account, placement.service == .googleDrive,
           accounts.first(where: { $0.email == email })?.isPersonal ?? DriveAccount.consumerDomains.contains(email.split(separator: "@").last.map { $0.lowercased() } ?? ""),
           accounts.contains(where: { !$0.isPersonal && $0.state == .ready }) {
            issues.append(.personalAccount(email))
        }
        let synced = placement.isSynced && placement.kind != .driveTop && !placement.inTrash
        var uploaded: PlacementCheckRow.State = .unknown
        if synced {
            if let error = facts.uploadError { issues.append(.uploadFailed(error)); uploaded = .failed }
            else if facts.driveItemID != nil || facts.uploaded == true { uploaded = .ok }
            else if facts.uploading == true || (placement.service == .googleDrive && !waitedLong) { issues.append(.notUploaded); uploaded = .waiting }
        }
        if facts.manifestOnlineOnly { issues.append(.onlineOnly) }
        self.issues = issues.enumerated().sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }.map(\.element)
        rows = [
            PlacementCheckRow(label: synced ? placement.label : "Synced folder", state: synced ? .ok : .failed),
            PlacementCheckRow(label: placement.service == .googleDrive ? "Uploaded to Drive" : "Uploaded", state: synced ? uploaded : .failed),
            PlacementCheckRow(label: "Not in the Trash", state: placement.inTrash ? .failed : .ok),
        ]
    }
}
