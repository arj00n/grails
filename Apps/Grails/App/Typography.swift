import AppKit
import CoreText
import GrailsDesign
import GrailsKit
import SwiftUI

/// Geist for text, Geist Bold for titles. Registered at launch from the app bundle.
enum Typeface {
    private static func data(_ file: (name: String, ext: String)) -> Data? {
        Bundle.main.url(forResource: file.name, withExtension: file.ext).flatMap { try? Data(contentsOf: $0) }
    }

    @MainActor static func register() {
        for file in [Typography.bodyFile, Typography.bodyBoldFile] {
            if let url = Bundle.main.url(forResource: file.name, withExtension: file.ext) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        // exports carry the same fonts
        ExportFonts.body = data(Typography.bodyFile)
        ExportFonts.bodyBold = data(Typography.bodyBoldFile)
    }
}

extension Font {
    /// Geist; `bold` is its true bold.
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> Font {
        ChromeFont.body(Double(size), bold: bold)
    }

    /// Geist Bold, for titles. The caller passes a size.
    static func grailsTitle(_ size: CGFloat) -> Font { ChromeFont.title(Double(size)) }
}

extension NSFont {
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> NSFont {
        ChromeNSFont.body(size, bold: bold)
    }

    /// Geist Bold, for titles. The caller passes a size.
    static func grailsTitle(_ size: CGFloat) -> NSFont {
        ChromeNSFont.title(size)
    }

    /// Geist with tabular digits, for a count beside a title.
    static func grailsDigits(_ size: CGFloat) -> NSFont {
        let base = grailsBody(size)
        let feature: [NSFontDescriptor.FeatureKey: Int] = [
            .typeIdentifier: Int(kNumberSpacingType),
            .selectorIdentifier: Int(kMonospacedNumbersSelector),
        ]
        let described = base.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return NSFont(descriptor: described, size: size) ?? base
    }
}
