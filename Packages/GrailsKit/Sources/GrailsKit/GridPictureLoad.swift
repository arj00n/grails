import AppKit
import Foundation

/// Getting a grid's cells built without waiting for a click.
public enum GridPictureLoad: Sendable {
    /// NSCollectionView creates item views when it is displayed, not when it is reloaded.
    /// Switching Canvas to Grid reloads before that display, so the cells stay empty until a click
    /// lays the scroll view out. Laying out the scroll view and displaying now is what a click was doing.
    @MainActor
    public static func materialize(_ view: NSView) {
        guard view.window != nil else { return }
        view.superview?.layoutSubtreeIfNeeded()
        view.enclosingScrollView?.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 1, view.bounds.height > 1 else { return }
        view.needsDisplay = true
        view.displayIfNeeded()
    }
}
