import Foundation

/// Geist for text, Geist Bold for a title or a section header. Both are SIL OFL, bundled unmodified.
public enum Typography {
    public static let bodyName = "Geist-Regular"
    public static let bodyBoldName = "Geist-Bold"
    /// CSS family. Weight picks the file.
    public static let bodyFamily = "Geist"

    /// (file name without extension, extension) as bundled.
    public static let bodyFile = (name: "Geist-Regular", ext: "ttf")
    public static let bodyBoldFile = (name: "Geist-Bold", ext: "ttf")

    /// Added to every body size so it sits beside the system font's sizes.
    public static let bodyBoost = 0.0
}
