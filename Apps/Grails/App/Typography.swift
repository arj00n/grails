import AppKit
import GrailsDesign
import SwiftUI

/// SF Pro through the system font; nothing is bundled or registered. Titles are SF Pro Rounded through the title token.
extension Font {
    /// SF Pro; `bold` is the emphasized (semibold) weight.
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> Font {
        ChromeFont.body(Double(size), bold: bold)
    }

    /// SF Pro Rounded Semibold, for titles, section headers, cluster names. The caller passes a size.
    static func grailsTitle(_ size: CGFloat) -> Font { ChromeFont.title(Double(size)) }

    /// SF Pro Rounded with tabular digits, for a count badge.
    static func grailsCount(_ size: CGFloat) -> Font { ChromeFont.count(Double(size)) }
}

extension NSFont {
    static func grailsBody(_ size: CGFloat, bold: Bool = false) -> NSFont {
        ChromeNSFont.body(size, bold: bold)
    }

    /// SF Pro Rounded Semibold, for titles. The caller passes a size.
    static func grailsTitle(_ size: CGFloat) -> NSFont {
        ChromeNSFont.title(size)
    }

    /// SF Pro Rounded with tabular digits, for a count beside a title.
    static func grailsCount(_ size: CGFloat) -> NSFont {
        ChromeNSFont.count(size)
    }
}
