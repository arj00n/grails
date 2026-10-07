import Foundation

/// Where an invited library lives, carried in the invite link so the teammate's Grails can say exactly what's missing when it can't find
/// the library. Only the kind of place, the Shared drive's name and the account's domain: never an address or a path.
public struct LibraryHint: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case sharedDrive = "sd", myDrive = "md", dropbox = "db", oneDrive = "od", box = "bx", iCloud = "ic"
    }

    public var kind: Kind
    /// The Shared drive's name (nil for anything else).
    public var place: String?
    /// The Google account's domain, `studio.com` (Google Drive only).
    public var domain: String?

    public init(kind: Kind, place: String? = nil, domain: String? = nil) { self.kind = kind; self.place = place; self.domain = domain }

    /// Nil for places teammates can't get (this Mac, the Trash, a computer backup).
    public init?(placement: Placement) {
        guard !placement.inTrash else { return nil }
        let domain = placement.account.flatMap { $0.split(separator: "@").last.map { $0.lowercased() } }
        switch placement.kind {
        case .sharedDrive(let d): self.init(kind: .sharedDrive, place: d, domain: domain)
        case .myDrive, .sharedWithMe: self.init(kind: .myDrive, domain: domain)
        case .cloud(.dropbox): self.init(kind: .dropbox)
        case .cloud(.oneDrive): self.init(kind: .oneDrive)
        case .cloud(.box): self.init(kind: .box)
        case .cloud(.iCloud): self.init(kind: .iCloud)
        case .cloud(.googleDrive): self.init(kind: .myDrive, domain: domain)
        case .local, .driveTop, .otherComputers: return nil
        }
    }

    public var service: CloudService {
        switch kind {
        case .sharedDrive, .myDrive: .googleDrive
        case .dropbox: .dropbox
        case .oneDrive: .oneDrive
        case .box: .box
        case .iCloud: .iCloud
        }
    }

    /// A personal (gmail.com) Drive: any Google account could have been given access, so the domain says nothing.
    public var isConsumerDomain: Bool { domain.map(DriveAccount.consumerDomains.contains) ?? false }

    var queryItems: [URLQueryItem] {
        var q = [URLQueryItem(name: "k", value: kind.rawValue)]
        if let place, !place.isEmpty { q.append(URLQueryItem(name: "at", value: place)) }
        if let domain, !domain.isEmpty { q.append(URLQueryItem(name: "dom", value: domain)) }
        return q
    }

    init?(items: [URLQueryItem]) {
        func value(_ k: String) -> String? { items.first { $0.name == k }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        guard let raw = value("k"), let kind = Kind(rawValue: raw) else { return nil }
        self.init(kind: kind, place: value("at").map { String($0.prefix(80)) }, domain: value("dom").map { String($0.prefix(80)).lowercased() })
    }

    /// "the Shared drive “Design” in our studio.com Google Drive", "a folder in my Google Drive", "Dropbox".
    public var whereSentence: String {
        let drive = (domain.map { isConsumerDomain ? "Google Drive" : "\($0) Google Drive" }) ?? "Google Drive"
        switch kind {
        case .sharedDrive: return place.map { "the Shared drive “\($0)” in our \(drive)" } ?? "a Shared drive in our \(drive)"
        case .myDrive: return "a folder in my \(drive)"
        case .dropbox, .oneDrive, .box, .iCloud: return "a shared folder in \(service.label)"
        }
    }
}

/// The words and links of an invite, and of the reply a teammate sends when the library can't be found.
public enum InviteText {
    public static let grailsSite = "https://grails.arjoon.xyz"

    /// The invite link: the router page with the library id, its name and where it lives after the `#` (never sent to the web server).
    public static func link(libraryID: String, name: String, hint: LibraryHint?, page: URL) -> URL {
        GrailsLink(library: libraryID, name: name, hint: hint).webURL(page: page)
    }

    public struct Message: Equatable, Sendable {
        public var subject: String
        public var body: String
    }

    /// The invite: one short message for everyone. The link is the same; Grails on their Mac shows the steps for their situation.
    public static func invite(library: String, link: URL, hint: LibraryHint?, from sender: String) -> Message {
        var lines = ["Hi,", ""]
        lines.append("I've set up \(library), our team's picture library in Grails." + (hint.map { " It lives in \($0.whereSentence)." } ?? ""))
        lines.append("")
        lines.append("1. Install Grails: \(grailsSite)")
        lines.append("2. Open this link: \(link.absoluteString)")
        lines += ["", "Grails shows the steps on your Mac.", ""]
        if !sender.isEmpty { lines.append(sender) }
        return Message(subject: "Join \(library) on Grails", body: lines.joined(separator: "\n"))
    }

    /// What a teammate sends back when Grails can't find the library: which library, what they need, and the address to add.
    public static func accessRequest(library: String, hint: LibraryHint?, myEmails: [String], link: URL?) -> Message {
        let me = myEmails.first.map { " (\($0))" } ?? ""
        let ask: String
        switch hint?.kind {
        case .sharedDrive?: ask = hint?.place.map { "Could you add me\(me) to the Shared drive “\($0)” as a Content manager?" } ?? "Could you add me\(me) to the Shared drive it's in, as a Content manager?"
        case .myDrive?: ask = "Could you share the folder with me\(me) as an Editor?"
        case nil: ask = "Could you share it with me\(me)?"
        default: ask = "Could you share the folder with me\(me) in \(hint!.service.label)?"
        }
        var lines = ["Hi,", "", "I opened the invite to \(library), but Grails can't find the library on my Mac. \(ask)"]
        if let link { lines += ["", "The invite: \(link.absoluteString)"] }
        lines += ["", "Thanks!"]
        return Message(subject: "Access to \(library)", body: lines.joined(separator: "\n"))
    }
}
