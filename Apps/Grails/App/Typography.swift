import AppKit
import CoreText
import GrailsDesign
import GrailsKit
import SwiftUI

/// Geist Mono for titles, Geist for the rest. Registered at launch from the app bundle.
enum Typeface {
    private static func data(_ file: (name: String, ext: String)) -> Data? {
        Bundle.main.url(forResource: file.name, withExtension: file.ext).flatMap { try? Data(contentsOf: $0) }
    }

    @MainActor static func register() {
        for file in [Typography.displayFile, Typography.bodyFile, Typography.bodyBoldFile] {
            if let url = Bundle.main.url(forResource: file.name, withExtension: file.ext) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        // exports carry the same fonts
        ExportFonts.display = data(Typography.displayFile)
        ExportFonts.body = data(Typography.bodyFile)
        ExportFonts.bodyBold = data(Typography.bodyBoldFile)
    }
}

extension Font {
    /// Geist; `bold` is its true bold.
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? Typography.bodyBoldName : Typography.bodyName, fixedSize: size + CGFloat(Typography.bodyBoost))
    }

    /// Geist Mono, for titles.
    static func grailsDisplay(_ size: CGFloat) -> Font { .custom(Typography.displayName, fixedSize: size) }
}

extension NSFont {
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? Typography.bodyBoldName : Typography.bodyName, size: size + CGFloat(Typography.bodyBoost)) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func grailsDisplay(_ size: CGFloat) -> NSFont {
        NSFont(name: Typography.displayName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
