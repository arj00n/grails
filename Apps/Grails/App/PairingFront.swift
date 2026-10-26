import AppKit
import GrailsDesign

/// Brings the library window forward for one new pairing id.
/// `MenuBarController.openApp` does not deminiaturize, and a miniaturized window is not visible, so `grailsSheet` would drop the request.
@MainActor
enum PairingFront {
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = host() else { return }
        if NSApp.isHidden || window.isMiniaturized || !window.isVisible {
            NSApp.unhide(nil)
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func host() -> NSWindow? {
        if let home = GrailsModalLayer.shared.home { return home }
        return NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) && $0.sheetParent == nil }
    }
}
