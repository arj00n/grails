import Foundation
import GrailsEndpoints

/// 4 · 6 · 8 · 12 · 16 · 20 · 24 · 32 · 40. Modal side padding sits on this scale.
public enum Space {
    public static let xxs = 4.0
    public static let tight = 6.0
    public static let xs = 8.0
    public static let sm = 12.0
    public static let md = 16.0
    public static let lg = 20.0
    public static let xl = 24.0
    public static let xxl = 32.0
    public static let xxxl = 40.0
    public static let control = 32.0
    public static let button = 28.0
    public static let quiet = 24.0
    public static let scale = [xxs, tight, xs, sm, md, lg, xl, xxl, xxxl]
}

/// Where every toast sits, errors included: centred across the whole window, `Space.xl` above its bottom edge. The whole window,
/// not the content beside the sidebar, so showing or hiding the sidebar never moves it. Cards that stack with it (progress)
/// share the same column, `Space.xs` apart.
public enum ToastPlacement {
    public static let bottomInset = Space.xl
    public static let stackSpacing = Space.xs

    /// The toast's frame in a window `width` × `height` (origin top-left), for a toast of `size`.
    public static func frame(windowWidth width: Double, windowHeight height: Double, size: (width: Double, height: Double)) -> (x: Double, y: Double, width: Double, height: Double) {
        let w = min(size.width, width)
        return ((width - w) / 2, height - bottomInset - size.height, w, size.height)
    }
}

/// Window 12, sheet 14, row 10, control 8, thumb and quiet 6, sidebar item 7.
public enum RadiusToken {
    public static let control = 8.0
    public static let chip = 6.0
    public static let card = 12.0
    public static let tile = 6.0
    public static let window = 12.0
    public static let row = 10.0
    public static let sidebarItem = 7.0
    public static let sheet = 14.0
}

public enum TypeScale {
    /// Geist Bold. Settings and empty pages.
    public static let page = 20.0
    /// Geist Bold. Sheet and window titles.
    public static let title = 15.0
    public static let subtitle = 13.0
    /// Geist Bold. Section headers such as People.
    public static let section = 13.0
    /// Geist Regular, secondary. The name of a field.
    public static let label = 12.0
    public static let body = 13.0
    public static let button = 13.0
    public static let quiet = 12.0
    /// Helper, meta, and row subtitles.
    public static let help = 12.0
    /// Invite link. Geist Regular, tabular digits, no tracking.
    public static let inviteLink = 12.0
    /// Invite code. Geist Regular, tabular digits, no tracking. Same size as a sheet title, different face.
    public static let inviteCode = 15.0
    /// -0.02em of the page title, in points.
    public static let pageTracking = -0.4
    /// -0.01em of the sheet title, in points.
    public static let titleTracking = -0.15
}

/// Which palette token a chrome role uses. Views read `Palette`; they do not pick their own hex.
public enum ChromeRole {
    public static let label = Token.secondary
    public static let section = Token.text
    /// The required mark matches the label. There is no accent colour.
    public static let required = Token.secondary
    public static let error = Token.text
    public static let fieldFill = Token.surface
    public static let fieldBorder = Token.hairline
    public static let fieldFocus = Token.focus
    public static let help = Token.tertiary
}

public enum ChromeMetrics {
    public static let fieldHeight = 32.0
    public static let iconButton = 24.0
    /// The only inset inside a field or a chooser card. Text, placeholder, caret, and icons share it.
    public static let fieldInset = 10.0
    /// The only gap between a label and its field.
    public static let labelGap = Space.tight
    /// Gap under a section header, before its rows.
    public static let fieldGap = Space.sm
    /// Gap between field groups (label, control, and helper).
    public static let groupGap = Space.lg
    /// Gap between a control and its helper.
    public static let helperGap = Space.xs
    public static let sectionGap = Space.xl
    public static let cardHeight = 40.0
    /// A disabled primary keeps the ink fill, faded. It does not become an outline.
    public static let disabledPrimary = 0.4
    public static let requiredMark = "*"
    public static let maxBody = 480.0
}

/// A Settings group: a small secondary label, then a raised card that holds the section's rows. Space between rows, no rules.
public enum SettingsGroupMetrics {
    /// The label sits a little in from the card's edge, toward the rows' text.
    public static let labelInset = Space.xs
    public static let labelGap = Space.xs
    public static let radius = RadiusToken.card
    public static let cardInsetY = Space.xxs
    public static let rowInsetX = Space.md
    public static let rowInsetY = Space.xs
    public static let rowHeight = ChromeMetrics.fieldHeight
    /// Between one group and the next.
    public static let groupGap = Space.xxl
    public static let fill = Token.group
    public static let border = Token.hairline
}

public enum ChromeIcon {
    public static let paste = "doc.on.clipboard"
    public static let reveal = "eye"
    public static let conceal = "eye.slash"
    public static let back = "chevron.left"
    public static let close = "xmark"
    public static let error = "exclamationmark.circle"
    public static let folder = "folder"
    public static let bucket = "externaldrive"
    public static let invite = "envelope"
    public static let people = "person.2"
    public static let trash = "trash"
    public static let chevronRight = "chevron.right"
    public static let chevronDown = "chevron.down"
    public static let key = "key"
    public static let link = "link"
    public static let copy = "doc.on.doc"
    public static let member = "person"
    public static let admin = "shield"
}

public enum KeychainNoticeCopy {
    public static let title = "macOS will ask for your password"
    public static let body = "Grails keeps the keys to your team storage in your Mac's Keychain. Until Apple has checked Grails, macOS asks once after each install or update. Enter your Mac login password and click Always Allow."
    public static let action = "Continue"
    public static let symbol = ChromeIcon.key
}

/// The confirm step in front of a bucket action that can't be undone. `GrailsConfirmModal` shows it.
public enum DestructiveConfirm: Equatable, Identifiable, Sendable {
    case deleteLibrary
    case emptyTrash
    case deleteOldBucket
    case restoreDay(String)

    public var id: String {
        switch self {
        case .deleteLibrary: "delete-library"
        case .emptyTrash: "empty-trash"
        case .deleteOldBucket: "delete-old-bucket"
        case .restoreDay: "restore-day"
        }
    }

    public var title: String {
        switch self {
        case .deleteLibrary: "Delete this library?"
        case .emptyTrash: "Empty Trash?"
        case .deleteOldBucket: "Delete the old team storage?"
        case .restoreDay(let day): "Restore \(day)?"
        }
    }

    public var message: String {
        switch self {
        case .deleteLibrary: "Every reference in this library is deleted, for everyone on the team. This can't be undone."
        case .emptyTrash: "Everything in the Trash is deleted, for everyone on the team. This can't be undone."
        case .deleteOldBucket: "Everything left in the team storage this library moved from is deleted. This can't be undone."
        case .restoreDay(let day): "Files from the \(day) backup replace the library's copies, for everyone on the team."
        }
    }

    public var action: String {
        switch self {
        case .deleteLibrary: "Delete library"
        case .emptyTrash: "Empty Trash"
        case .deleteOldBucket: "Delete old storage"
        case .restoreDay: "Restore"
        }
    }

    public var symbol: String {
        switch self {
        case .restoreDay: "clock.arrow.circlepath"
        default: ChromeIcon.trash
        }
    }
}

public enum ChromeState: String, CaseIterable, Sendable {
    case normal, hover, focus, disabled, error, loading
}

public enum ModalMetrics {
    public static let width = 440.0
    public static let padding = Space.xl
    public static let paddingTop = Space.lg
    public static let footerGap = 28.0
    public static let buttonGap = Space.xs
    public static let gap = Space.lg
    /// A step with no footer actions draws no divider and no footer band.
    public static let hidesEmptyFooter = true
}

/// How a modal arrives through `GrailsModalLayer`. The window it sits in draws nothing of its own: no frame, fill, shadow or
/// system sheet slide. The card (frame, fill, shadow and contents) is one piece that settles from the top on the sheet spring,
/// and the scrim behind it only fades. Leaving is one quick fade of both.
public enum ModalPresentation {
    /// The canvas wash over the window under a modal.
    public static let scrimOpacity = 0.55

    /// Where the card hangs from: a seventh of the way down the window it covers, never closer to the top than 48.
    public static func cardTop(windowHeight: Double) -> Double { max(48, (windowHeight / 7).rounded()) }

    public struct Pose: Equatable, Sendable {
        public var scale: Double
        public var offsetY: Double
        public var opacity: Double
    }

    /// The card before and after it arrives. It scales about its top edge and drops into place; under Reduce Motion it only fades.
    public static func card(arrived: Bool, reduceMotion: Bool) -> Pose {
        if arrived { return Pose(scale: 1, offsetY: 0, opacity: 1) }
        if reduceMotion { return Pose(scale: 1, offsetY: 0, opacity: 0) }
        return Pose(scale: Motion.overlayScale, offsetY: -Motion.overlayDrop, opacity: 1)
    }

    /// The scrim never moves or scales.
    public static func scrim(arrived: Bool) -> Pose { Pose(scale: 1, offsetY: 0, opacity: arrived ? 1 : 0) }
}

/// Spring Cleaning. The card is the modal body, and the sheet has to be at least that tall. A shorter window is the blank strip.
public enum SpringSheetLayout {
    public static var cardSide: CGFloat { CGFloat(ModalMetrics.width - ModalMetrics.padding * 2) }
    /// How far the next card peeks out under the front one.
    public static let peek: CGFloat = 16
    public static var deckHeight: CGFloat { cardSide + peek }
    /// Title band, the deck, and the keep/chuck row.
    public static var minimumHeight: CGFloat {
        CGFloat(ModalMetrics.paddingTop + Space.lg + ModalMetrics.footerGap + Space.button + ModalMetrics.padding) + deckHeight
    }
}

/// The hairline between a modal body and its footer. It is absent unless both sides have something to separate.
public enum ModalDivider {
    public static func shows(hasBody: Bool, hasFooter: Bool, scrolls: Bool) -> Bool {
        hasBody && hasFooter && scrolls
    }
}

/// A divider is a 1- or 2-pixel hairline run with a non-hairline row on both sides. A solid fill is not a line.
public enum ModalDividerScan {
    public static func runs(_ hairline: [Bool]) -> Int {
        var count = 0
        var index = 0
        while index < hairline.count {
            if hairline[index] {
                let start = index
                while index < hairline.count, hairline[index] { index += 1 }
                let thickness = index - start
                let bordered = start > 0 && index < hairline.count && !hairline[start - 1] && !hairline[index]
                if (1...2).contains(thickness), bordered { count += 1 }
            } else {
                index += 1
            }
        }
        return count
    }
}

/// One container. Steps replace the page inside it. The motion stays inside `Motion.longest`.
public enum ModalMotion {
    public static let duration = Motion.standard
    public static let slide = 8.0
    public static let curve = Motion.standardCurve
    public static let kind = "crossfadeSlide"
}

public struct ModalSession: Equatable, Sendable {
    public let containerID: String
    public private(set) var pageID: String
    public var presentedModals: Int { 1 }

    public init(containerID: String, pageID: String) {
        self.containerID = containerID
        self.pageID = pageID
    }

    public mutating func swap(to pageID: String) {
        self.pageID = pageID
    }
}

public enum GrailsButtonKind: String, CaseIterable, Sendable {
    case primary, secondary, quiet, destructive
}

public struct FieldSpec: Equatable, Sendable {
    public var id: String
    public var label: String
    public var required: Bool
    public var secure: Bool
    public var section: String
    public var placeholder: String
    /// Hidden until the person opens the disclosure. Region is the one advanced field.
    public var advanced: Bool

    public init(id: String, label: String, required: Bool, secure: Bool, section: String, placeholder: String = "", advanced: Bool = false) {
        self.id = id
        self.label = label
        self.required = required
        self.secure = secure
        self.section = section
        self.placeholder = placeholder
        self.advanced = advanced
    }
}

public enum FormOrder {
    public static func next(after id: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: id), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    public static func previous(before id: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: id), index > 0 else { return nil }
        return order[index - 1]
    }
}

public enum FieldRules {
    public static func canCreateBucket(endpoint: String, bucket: String, accessKey: String, secret: String, email: String) -> Bool {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard httpEndpoint(endpoint), !bucket.isEmpty, !accessKey.isEmpty, !secret.isEmpty, email.contains("@") else { return false }
        return true
    }

    public static func httpEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return false }
        return true
    }

    public static func regionOrDefault(_ region: String) -> String {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? BucketDraft.regionDefault : trimmed
    }

    public static func endpointError(_ endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || httpEndpoint(trimmed) { return nil }
        return "Check the endpoint"
    }

    public static func emailError(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("@") { return nil }
        return "Check the email"
    }

    public static func inviteCode(_ raw: String) -> String? {
        let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 6, digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    public static func codeError(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || inviteCode(trimmed) != nil { return nil }
        return "Check the join code"
    }

    public static func linkError(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || inviteLink(in: trimmed) { return nil }
        return "Check the link"
    }

    /// Same shape as `JoinLink.find`: `grails://j/<payload>`, `grails://i/<id>`, a legacy `grails://join` link, `<site>/i/<id>` (`GrailsEndpoints.site`), or an https link whose fragment is one of the app links.
    public static func inviteLink(in text: String) -> Bool {
        for part in text.split(whereSeparator: \.isWhitespace) {
            let trimmed = part.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'.,"))
            if let url = URL(string: String(trimmed)), parseInvite(url) { return true }
        }
        return false
    }

    private static func parseInvite(_ url: URL) -> Bool {
        if idOnlyInvite(url) { return true }
        if shortInvite(url) { return true }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let fragment = url.fragment, !fragment.isEmpty {
            if fragmentValue(fragment, name: "j") != nil { return true }
            if let inner = URL(string: "grails://join?" + fragment) { return parseInvite(inner) }
            return false
        }
        if url.scheme?.lowercased() == "grails", url.host?.lowercased() == "j" {
            return !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        }
        guard url.scheme?.lowercased() == "grails", url.host?.lowercased() == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty,
              let blob = items.first(where: { $0.name == "blob" })?.value, !blob.isEmpty else { return false }
        return true
    }

    /// `grails://i/<id>` claims inside the app. The length and alphabet match `InviteRelay.isShortID`.
    private static func idOnlyInvite(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "grails", url.host?.lowercased() == "i" else { return false }
        return acceptsShortID(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// Keep the length and alphabet in step with `InviteRelay.isShortID`.
    /// Only the build's own site mints short links. A build with no site has none.
    private static func shortInvite(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = GrailsEndpoints.site?.host?.lowercased(),
              url.host?.lowercased() == host else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "i" else { return false }
        return acceptsShortID(parts[1])
    }

    private static func acceptsShortID(_ id: String) -> Bool {
        guard (8...22).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { ShortInviteID.characters.contains($0) }
    }

    private static func fragmentValue(_ fragment: String, name: String) -> String? {
        for part in fragment.split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2, pieces[0] == name, !pieces[1].isEmpty else { continue }
            return pieces[1]
        }
        return nil
    }
}

public struct BucketDraft: Equatable, Sendable {
    public static let bucketSection = "Bucket"
    public static let invitesSection = "Invites"
    public static let invitesTag = "Optional"
    public static let invitesDetail = "Creates teammate keys in Cloudflare."
    public static let regionDefault = "auto"

    public var endpoint: String
    public var bucket: String
    public var region: String
    public var accessKey: String
    public var secret: String
    public var email: String
    public var accountID: String
    public var apiToken: String

    public init(endpoint: String = "", bucket: String = "", region: String = regionDefault, accessKey: String = "", secret: String = "", email: String = "", accountID: String = "", apiToken: String = "") {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.accessKey = accessKey
        self.secret = secret
        self.email = email
        self.accountID = accountID
        self.apiToken = apiToken
    }

    public static let fields: [FieldSpec] = [
        FieldSpec(id: "endpoint", label: "Endpoint", required: true, secure: false, section: bucketSection, placeholder: "https://<account>.r2.cloudflarestorage.com"),
        FieldSpec(id: "bucket", label: "Bucket", required: true, secure: false, section: bucketSection, placeholder: "grails"),
        FieldSpec(id: "region", label: "Region", required: false, secure: false, section: bucketSection, placeholder: "auto", advanced: true),
        FieldSpec(id: "accessKey", label: "Access key", required: true, secure: false, section: bucketSection),
        FieldSpec(id: "secret", label: "Secret", required: true, secure: true, section: bucketSection),
        FieldSpec(id: "email", label: "Your email", required: true, secure: false, section: bucketSection, placeholder: "name@company.com"),
        FieldSpec(id: "accountID", label: "Account", required: false, secure: false, section: invitesSection),
        FieldSpec(id: "apiToken", label: "API token", required: false, secure: true, section: invitesSection),
    ]

    public static func field(_ id: String) -> FieldSpec {
        fields.first { $0.id == id } ?? fields[0]
    }

    /// Region stays out of the tab order until its disclosure is open.
    public static func tabOrder(showingAdvanced: Bool) -> [String] {
        fields.filter { showingAdvanced || !$0.advanced }.map(\.id)
    }

    public static var tabOrder: [String] { tabOrder(showingAdvanced: false) }

    public static func submitsOnReturn(from field: String) -> Bool {
        fields.contains { $0.id == field }
    }

    public var canCreate: Bool {
        FieldRules.canCreateBucket(endpoint: endpoint, bucket: bucket, accessKey: accessKey, secret: secret, email: email)
    }

    public var regionForSave: String { FieldRules.regionOrDefault(region) }

    public var endpointError: String? { FieldRules.endpointError(endpoint) }
    public var emailError: String? { FieldRules.emailError(email) }
}

public struct InviteDraft: Equatable, Sendable {
    public var link: String
    public var code: String

    public init(link: String = "", code: String = "") {
        self.link = link
        self.code = code
    }

    public static let fields: [FieldSpec] = [
        FieldSpec(id: "link", label: "Invite link", required: true, secure: false, section: "Invite"),
        FieldSpec(id: "code", label: "Code", required: true, secure: false, section: "Invite"),
    ]

    public static var tabOrder: [String] { fields.map(\.id) }

    public static func submitsOnReturn(from field: String) -> Bool {
        fields.contains { $0.id == field }
    }

    public var canContinue: Bool {
        FieldRules.inviteLink(in: link) && FieldRules.inviteCode(code) != nil
    }

    public var linkError: String? { FieldRules.linkError(link) }
    public var codeError: String? { FieldRules.codeError(code) }
}

public enum WorkspaceStep: String, Equatable, Sendable, CaseIterable {
    case choose, bucket, invite

    public var title: String {
        switch self {
        case .choose: "New workspace"
        case .bucket: "Team storage"
        case .invite: "Join with invite"
        }
    }
}

/// Chooser, bucket, and invite are pages of one sheet. `go` never opens a second one.
public struct WorkspaceFlow: Equatable, Sendable {
    public let containerID: String
    public private(set) var step: WorkspaceStep
    public var bucket: BucketDraft
    public var invite: InviteDraft
    public var presentedModals: Int { 1 }

    public init(start: WorkspaceStep, containerID: String = "workspace") {
        self.containerID = containerID
        self.step = start
        self.bucket = BucketDraft()
        self.invite = InviteDraft()
    }

    public mutating func go(_ step: WorkspaceStep) {
        self.step = step
    }

    public var canSubmit: Bool {
        switch step {
        case .choose: false
        case .bucket: bucket.canCreate
        case .invite: invite.canContinue
        }
    }
}

private enum ShortInviteID {
    static let characters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
}
