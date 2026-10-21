import Foundation

/// The website a build talks to: the short-invite relay (`/api/invite`, `/i/<id>`), the link page (`/open`) and the install link in invites.
/// The app's Info.plist sets `GrailsSiteURL` from `GRAILS_SITE_URL` (Config/Base.xcconfig). A build that leaves it empty has no site:
/// invites stay long `grails://` links and nothing is sent to a relay. Without the key at all (`swift test`, the CLI) the official site is used.
public enum GrailsEndpoints {
    public static let infoKey = "GrailsSiteURL"
    public static let officialSite = URL(string: "https://grails.arjoon.xyz")!

    public static let site: URL? = site(infoValue: Bundle.main.object(forInfoDictionaryKey: infoKey))

    /// Nil key → the official site. Empty, unexpanded or non-https → no site.
    public static func site(infoValue: Any?) -> URL? {
        guard let infoValue else { return officialSite }
        guard let text = (infoValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.contains("$("), let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return text.hasSuffix("/") ? URL(string: String(text.dropLast())) : url
    }

    /// The page that hands a link to the app, or nil when there is no site.
    public static var linkPage: URL? { site?.appendingPathComponent("open") }
}
