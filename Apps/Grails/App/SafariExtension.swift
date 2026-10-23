import Foundation

/// Whether this build ships the Safari web extension.
///
/// True only when Info.plist key `GRAILS_SAFARI_EXTENSION` is the string `YES`.
/// That key is the build setting of the same name (`Config/Base.xcconfig`, default `NO`).
enum SafariExtension {
    static let infoKey = "GRAILS_SAFARI_EXTENSION"

    static var isAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String) == "YES"
    }
}
