import AppKit
import CoreText
import GrailsDesign
import GrailsKit
import SwiftUI

/// VCR OSD Mono for titles, Alte Haas Grotesk for the rest. Registered at launch from the app bundle.
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
    /// Alte Haas Grotesk; `bold` is its true bold.
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? Typography.bodyBoldName : Typography.bodyName, fixedSize: size + CGFloat(Typography.bodyBoost))
    }

    /// VCR OSD Mono, for titles. The size snaps to the sizes the pixel face is crisp at.
    static func grailsDisplay(_ size: CGFloat) -> Font { .custom(Typography.displayName, fixedSize: CGFloat(Typography.displaySize(for: Double(size)))) }
}

extension NSFont {
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? Typography.bodyBoldName : Typography.bodyName, size: size + CGFloat(Typography.bodyBoost)) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func grailsDisplay(_ size: CGFloat) -> NSFont {
        NSFont(name: Typography.displayName, size: CGFloat(Typography.displaySize(for: Double(size)))) ?? .systemFont(ofSize: size, weight: .semibold)
    }
}
