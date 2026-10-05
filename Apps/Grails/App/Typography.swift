import AppKit
import CoreText
import GrailsDesign
import GrailsKit
import SwiftUI

/// Basteleur Bold for titles, Projekt Blackbird for the rest. Registered at launch from the app bundle.
enum Typeface {
    @MainActor static func register() {
        for file in [Typography.displayFile, Typography.bodyFile] {
            if let url = Bundle.main.url(forResource: file, withExtension: "otf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        // exports carry the same fonts
        ExportFonts.display = Bundle.main.url(forResource: Typography.displayFile, withExtension: "otf").flatMap { try? Data(contentsOf: $0) }
        ExportFonts.body = Bundle.main.url(forResource: Typography.bodyFile, withExtension: "otf").flatMap { try? Data(contentsOf: $0) }
    }
}

extension Font {
    /// Blackbird. One weight: use colour for emphasis.
    static func grailsBody(_ size: CGFloat) -> Font { .custom(Typography.bodyName, fixedSize: size + CGFloat(Typography.bodyBoost)) }
    /// Basteleur Bold, for titles.
    static func grailsDisplay(_ size: CGFloat) -> Font { .custom(Typography.displayName, fixedSize: size) }
}

extension NSFont {
    static func grailsBody(_ size: CGFloat) -> NSFont { NSFont(name: Typography.bodyName, size: size + CGFloat(Typography.bodyBoost)) ?? .systemFont(ofSize: size) }
    static func grailsDisplay(_ size: CGFloat) -> NSFont { NSFont(name: Typography.displayName, size: size) ?? .systemFont(ofSize: size, weight: .semibold) }
}
