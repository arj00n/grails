import AppKit

/// Menu bar item that doubles as a drop zone: drag images, files or links onto it and they land in the Inbox.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        super.init()
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Grails")
        button.toolTip = "Grails: drop images, files or links here to save them to your Inbox"
        let drop = DropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onDrop = { [weak model] pb in model?.paste(toInbox: true, from: pb) }
        drop.onClick = { [weak self] in self?.statusItem.button?.performClick(nil) }
        button.addSubview(drop)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Grails", action: #selector(openApp), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Save Clipboard to Inbox", action: #selector(saveClipboard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let dock = menu.addItem(withTitle: "Hide Dock Icon", action: #selector(toggleDock), keyEquivalent: "")
        dock.target = self
        dock.state = UserDefaults.standard.bool(forKey: "hideDockIcon") ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Grails", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain }) { w.makeKeyAndOrderFront(nil) }
    }

    @objc private func saveClipboard() { model?.paste(toInbox: true) }

    @objc private func toggleDock() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "hideDockIcon"), forKey: "hideDockIcon")
        model?.applyDockPolicy()
        openApp()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}

private final class DropView: NSView {
    var onDrop: ((NSPasteboard) -> Void)?
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard)
        return true
    }
}
