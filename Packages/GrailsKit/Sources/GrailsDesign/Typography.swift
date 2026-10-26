import Foundation

/// SF Pro, the system font. No font file is bundled or registered.
/// Text is SF Pro (the default design), regular, semibold when a row title needs weight. A title, a section header, a
/// cluster name, an avatar initial and a count badge are SF Pro Rounded through the title and count tokens.
public enum Typography {
    public enum Design: String, Sendable { case standard, rounded }
    public enum Weight: String, Sendable { case regular, medium, semibold, bold }

    /// Body, list rows, controls, metadata.
    public static let bodyDesign = Design.standard
    public static let bodyWeight = Weight.regular
    /// `bold: true` on body text: semibold, macOS's emphasized body weight.
    public static let bodyEmphasisWeight = Weight.semibold

    /// The one title face: SF Pro Rounded Semibold.
    public static let titleDesign = Design.rounded
    public static let titleWeight = Weight.semibold

    /// Count badges: SF Pro Rounded, medium, tabular digits.
    public static let countDesign = Design.rounded
    public static let countWeight = Weight.medium

    /// CSS stacks for exports, the extension and the mockups: the same faces on the web.
    public static let cssBody = #"-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif"#
    public static let cssRounded = #"ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif"#
    /// CSS weight of a title.
    public static let cssTitleWeight = 600

    /// Added to every body size so it sits beside the system font's sizes.
    public static let bodyBoost = 0.0
}
