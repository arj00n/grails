import Foundation

/// How visible the preview's details column is.
///
/// Opening fades it in after the picture has left its tile. A finger dismiss fades it with the page.
/// Flying back onto a tile fades it out over the whole return, on the flight's own clock, so it is gone as the picture lands,
/// even on a tile under the column. `flight` is the stage's fade progress, which never turns back, so the fade never bounces.
public enum PreviewInfoFade {
    public static func opacity(flight: Double, dismiss: Double, returningToTile: Bool) -> Double {
        let f = min(max(flight, 0), 1)
        let revealed = returningToTile ? f : min(max((f - 0.4) / 0.6, 0), 1)
        let held = max(0, 1 - dismiss * 3)
        return revealed * held
    }
}
