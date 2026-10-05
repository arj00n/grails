import Foundation

/// The two typefaces: Basteleur Bold for titles, Projekt Blackbird for everything else. Blackbird has one weight (emphasis comes from
/// colour, not boldness) and a small, narrow face, so body sizes are nudged up to sit beside the system font's sizes.
public enum Typography {
    public static let displayName = "Basteleur-Bold"
    public static let bodyName = "ProjektBlackbird-Regular"
    public static let displayFile = "Basteleur-Bold"
    public static let bodyFile = "projekt-blackbird"

    /// Added to every body size so 13 looks like a 13 beside the system font.
    public static let bodyBoost = 1.0

    /// Body sizes used in the app, small to large; anything else should be one of these.
    public static let bodySizes: [Double] = [9, 10, 11, 12, 13, 14, 15, 16, 17]
    /// Title sizes: inspector/preview, dialog, section, empty state, welcome.
    public static let displaySizes: [Double] = [13, 14, 16, 18, 24, 26, 34]

    /// Characters Blackbird doesn't have; the system font fills in for these.
    public static let bodyMissing = "×…↗éüñøå₹←→"
}
