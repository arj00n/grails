import CoreGraphics
import Foundation

/// The picture's flight between its grid tile and its place on the preview page.
///
/// The tile can sit anywhere in the window, including under the details column on the right, which is outside the stage.
/// The flight keeps that rect as it is: the stage stops clipping while the picture is in the air, and the column fades on the
/// same clock, so a tile on the right is flown to exactly like any other.
public enum PreviewFlight {
    /// The whole picture fitted inside its tile (the tile crops it; the flight shows it whole).
    public static func tileFrame(tile: CGRect, image: CGSize) -> CGRect {
        let s = min(tile.width / max(image.width, 1), tile.height / max(image.height, 1))
        let w = image.width * s, h = image.height * s
        return CGRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h)
    }

    /// Where the picture is at `progress` (0 on its tile, 1 on the page). Not clamped: the spring's settle is spatial motion.
    public static func frame(tile: CGRect, page: CGRect, image: CGSize, progress: Double) -> CGRect {
        let from = tileFrame(tile: tile, image: image), f = CGFloat(progress)
        return CGRect(x: from.minX + (page.minX - from.minX) * f, y: from.minY + (page.minY - from.minY) * f,
                      width: from.width + (page.width - from.width) * f, height: from.height + (page.height - from.height) * f)
    }

    /// The stage clips its pages only when nothing is flying, so a tile outside it (under the details column) stays visible.
    public static func clipsStage(inFlight: Bool) -> Bool { !inFlight }

    /// The progress the page wash and the details column fade with. It follows the flight but never turns back, so the
    /// spring's settle moves the picture and never makes a fade bounce. `target` is where the flight is heading (0 or 1).
    public static func fade(previous: Double, flight: Double, target: Double) -> Double {
        let f = min(max(flight, 0), 1)
        return target >= 0.5 ? max(previous, f) : min(previous, f)
    }
}
