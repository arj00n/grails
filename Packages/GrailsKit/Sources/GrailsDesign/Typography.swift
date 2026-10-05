import Foundation

/// The two typefaces: VCR OSD Mono (a pixel monospace) for titles and Alte Haas Grotesk (a Helvetica-like grotesque, with a true bold)
/// for everything else. The pixel face is crisp only at certain sizes, so titles snap to a small scale.
public enum Typography {
    public static let displayName = "VCROSDMono"
    public static let bodyName = "AlteHaasGrotesk"
    public static let bodyBoldName = "AlteHaasGrotesk_Bold"
    /// Family names for CSS.
    public static let displayFamily = "VCR OSD Mono"
    public static let bodyFamily = "Alte Haas Grotesk"

    /// (file name without extension, extension) as bundled.
    public static let displayFile = (name: "VCR_OSD_MONO_1.001", ext: "ttf")
    public static let bodyFile = (name: "AlteHaasGroteskRegular", ext: "ttf")
    public static let bodyBoldFile = (name: "AlteHaasGroteskBold", ext: "ttf")

    /// Added to every body size so it sits beside the system font's sizes (Alte Haas already does).
    public static let bodyBoost = 0.0

    /// Title sizes the pixel face is drawn at.
    public static let displaySizes: [Double] = [12, 16, 20, 24, 32]

    /// The scale size closest to `requested` (halfway goes up).
    public static func displaySize(for requested: Double) -> Double {
        displaySizes.min { a, b in
            let da = abs(a - requested), db = abs(b - requested)
            return da == db ? a > b : da < db
        } ?? requested
    }
}
