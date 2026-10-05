import Foundation

/// The two typefaces: Geist Mono for titles and Geist for everything else (with a true bold). Both are SIL OFL, bundled unmodified.
public enum Typography {
    public static let displayName = "GeistMono-Regular"
    public static let bodyName = "Geist-Regular"
    public static let bodyBoldName = "Geist-Bold"
    /// Family names for CSS.
    public static let displayFamily = "Geist Mono"
    public static let bodyFamily = "Geist"

    /// (file name without extension, extension) as bundled.
    public static let displayFile = (name: "GeistMono-Regular", ext: "ttf")
    public static let bodyFile = (name: "Geist-Regular", ext: "ttf")
    public static let bodyBoldFile = (name: "Geist-Bold", ext: "ttf")

    /// Added to every body size so it sits beside the system font's sizes.
    public static let bodyBoost = 0.0
}
