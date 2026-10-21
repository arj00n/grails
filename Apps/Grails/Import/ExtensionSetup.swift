import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// A Chromium browser installed on this Mac, which the extension can go into.
struct ChromiumBrowser: Identifiable, Equatable {
    let id: String            // bundle identifier
    let name: String
    let url: URL

    static let known: [(name: String, id: String)] = [
        ("Chrome", "com.google.Chrome"), ("Arc", "company.thebrowser.Browser"), ("Brave", "com.brave.Browser"), ("Edge", "com.microsoft.edgemac"),
        ("Dia", "company.thebrowser.dia"), ("Vivaldi", "com.vivaldi.Vivaldi"), ("Opera", "com.operasoftware.Opera"),
    ]

    @MainActor static func installed() -> [ChromiumBrowser] {
        known.compactMap { k in NSWorkspace.shared.urlForApplication(withBundleIdentifier: k.id).map { ChromiumBrowser(id: k.id, name: k.name, url: $0) } }
    }

    /// The app's icon as a plain bitmap (drawn once), so it renders the same everywhere.
    @MainActor var icon: CGImage? {
        let size = NSSize(width: 72, height: 72)
        let image = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

enum ExtensionInstall {
    /// Save to Grails on the Chrome Web Store. Unlisted: the page is the install. An empty `extensionStoreURL` falls back to the unpacked folder.
    static let storeID = ExtensionOrigin.chromeStoreID
    static let listing = URL(string: "https://chromewebstore.google.com/detail/save-to-grails/\(storeID)")!

    static var storeURL: URL? {
        if let s = UserDefaults.standard.string(forKey: "extensionStoreURL") {
            if s.isEmpty { return nil }
            if let u = URL(string: s) { return u }
        }
        return listing
    }

    /// Browsers that install a store extension from a preferences file on their next launch. Arc and Dia do not.
    private static func externalDirectory(_ bundleID: String) -> URL? {
        let folder: String
        switch bundleID {
        case "com.google.Chrome": folder = "Google/Chrome"
        case "com.brave.Browser": folder = "BraveSoftware/Brave-Browser"
        case "com.vivaldi.Vivaldi": folder = "Vivaldi"
        default: return nil
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/External Extensions", isDirectory: true)
    }

    /// Asks `bundleID` to offer the store extension the next time it launches. Chrome then shows Enable. False when this browser
    /// doesn't read that file, or the folder can't be written.
    static func stage(bundleID: String) -> Bool {
        guard let dir = externalDirectory(bundleID) else { return false }
        guard let data = try? JSONSerialization.data(withJSONObject: ["external_update_url": "https://clients2.google.com/service/update2/crx"]) else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("\(storeID).json"), options: .atomic)
            return true
        } catch { return false }
    }
}

/// The "Add the extension" sheet: why, what it does, which browsers, Install; then it follows the install through to "Connected".
@MainActor @Observable
final class ExtensionSetup {
    var isOpen = false
    private(set) var browsers: [ChromiumBrowser] = []
    var selected = Set<String>()
    /// Opened because an import needs the extension: once it connects, the import starts by itself.
    var continueImport = false
    /// An extension connected while the sheet was open.
    var connected = false
    /// Install was clicked: the browsers were opened and we are waiting for the extension to ask to connect.
    private(set) var opened = false
    /// How the last Install reached the browser. The guide and the waiting steps follow this.
    enum Route { case store, staged, unpacked }
    private(set) var route: Route = .store
    var chosen: [ChromiumBrowser] { browsers.filter { selected.contains($0.id) } }

    func open(app: AppModel, continueImport: Bool = false) {
        browsers = ChromiumBrowser.installed()
        self.continueImport = continueImport
        opened = false
        connected = false
        let def = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { url in browsers.first { $0.url == url } }
        selected = Set([def ?? browsers.first].compactMap { $0?.id })
        route = ExtensionInstall.storeURL == nil ? .unpacked : .store
        isOpen = true
        // Settings ▸ Extensions asks for it as often as the library does: the layer puts it on whichever is in front
        GrailsModalLayer.shared.present(Self.modalID, onCancel: { [weak self] in self?.close() }) { ExtensionModal(model: app) }
    }

    func close() {
        isOpen = false
        GrailsModalLayer.shared.dismiss(Self.modalID)
    }

    private static let modalID = "extension-setup"

    func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }

    /// For the demo: a fixed set of browsers and a state to show.
    func demo(browsers: [ChromiumBrowser], selected: Set<String>, opened: Bool, connected: Bool = false) {
        self.browsers = browsers; self.selected = selected; self.opened = opened; self.connected = connected; isOpen = true
    }

    /// The browser the extension went into (the first ticked): the one imports that need it are opened in.
    static var preferredBrowser: URL? {
        guard let id = UserDefaults.standard.string(forKey: "extensionBrowser") else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    func install(app: AppModel) {
        let targets = chosen
        guard !targets.isEmpty else { return }
        UserDefaults.standard.set(targets[0].id, forKey: "extensionBrowser")
        let name = targets[0].name

        guard let store = ExtensionInstall.storeURL else {
            guard let copied = app.copyExtensionFolder() else { return }
            for b in targets { NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: b.url, configuration: NSWorkspace.OpenConfiguration()) }
            finish(app: app, route: .unpacked, name: name, folder: copied)
            return
        }

        // The preferences file is read only at launch. A browser that isn't open gets the extension that way (Enable).
        // One that's already open gets the store page now, and the same file for the next time it starts.
        var first: Route = .store
        for (index, b) in targets.enumerated() {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: b.id).isEmpty
            let staged = ExtensionInstall.stage(bundleID: b.id)
            if staged, !running {
                if index == 0 { first = .staged }
                NSWorkspace.shared.openApplication(at: b.url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                NSWorkspace.shared.open([store], withApplicationAt: b.url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        finish(app: app, route: first, name: name, folder: nil)
    }

    private func finish(app: AppModel, route: Route, name: String, folder: URL?) {
        opened = true
        self.route = route
        let steps: [(String, GuideModel.State)]
        switch route {
        case .staged:
            steps = [("Click Enable in \(name)", .current), ("Click Allow in Grails", .pending)]
        case .store:
            steps = [("Click Add to \(name) on the page that opened", .current), ("Confirm Add extension", .pending), ("Click Allow in Grails", .pending)]
        case .unpacked:
            steps = [("Turn on Developer mode, top right of the page", .current), ("Drag the folder below onto the page", .pending), ("Click Allow in Grails", .pending)]
        }
        app.guide.set(title: "Adding the extension", steps: steps, folder: folder)
        app.guidePanel.show()
        app.guidePanel.onClose = { [weak self] in self?.opened = false }
    }
}

struct ExtensionModal: View {
    var model: AppModel
    private var setup: ExtensionSetup { model.extensionSetup }

    private enum Stage { case choose, waiting, allow, connected }
    private var stage: Stage {
        if setup.connected { return .connected }
        if model.pairRequest != nil { return .allow }
        return setup.opened ? .waiting : .choose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(heading).font(.grailsDisplay(CGFloat(TypeScale.title))).foregroundStyle(Ink.text)
                Spacer()
                BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "extension-close") { setup.close() }
            }
            switch stage {
            case .choose: choose
            case .waiting: waiting
            case .allow: allow
            case .connected: connected
            }
            GrailsControl("") { setup.close() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: 460)
        .accessibilityIdentifier("extension-modal")
    }

    private var heading: String {
        switch stage {
        case .choose: "ADD THE EXTENSION"
        case .waiting: "ALMOST THERE"
        case .allow: "ALLOW IT IN"
        case .connected: "CONNECTED"
        }
    }

    // MARK: Choose

    private var choose: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pinterest only hands other apps the latest 50 pins of a board. The extension reads the whole board from your own browser, where you're already signed in, and passes it to Grails.")
                .font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                point("square.grid.2x2", "Imports full boards, and every board on a profile")
                point("cursorarrow.click.2", "Saves any image or page: right-click, or hold ⌥ and click")
                point("lock", "Stays on this Mac. It talks only to Grails, nothing online")
            }
            if setup.browsers.isEmpty {
                Text("No supported browser found. Install Chrome, Arc, Brave or Edge first.").font(.grailsBody(12)).foregroundStyle(Ink.destructive)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install in").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                    HStack(spacing: 8) { ForEach(setup.browsers) { b in BrowserTile(browser: b, selected: setup.selected.contains(b.id)) { setup.toggle(b.id) } } }
                }
            }
            VStack(spacing: 8) {
                GrailsButton(installLabel, kind: .primary, identifier: "extension-install", enabled: !setup.chosen.isEmpty) { setup.install(app: model) }
                    .keyboardShortcut(.defaultAction)
                GrailsButton("Not now", kind: .quiet) { setup.close() }
            }
        }
    }

    private var installLabel: String {
        switch setup.chosen.count {
        case 0: "Install extension"
        case 1: "Install in \(setup.chosen[0].name)"
        default: "Install in \(setup.chosen.count) browsers"
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(ChromeFont.symbol(12)).foregroundStyle(Ink.secondary).frame(width: 18)
            Text(text).font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: After Install

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                step(1, setup.route == .staged ? "Click Enable in \(setup.chosen.first?.name ?? "Chrome")"
                    : setup.route == .unpacked ? "Turn on Developer mode, then drag the Extension folder onto the page"
                    : "Click Add to \(setup.chosen.first?.name ?? "Chrome") in the tab that opened")
                step(2, "Click Allow in Grails")
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                StatusDot(.warn, "Waiting for the extension")
                Spacer()
                GrailsButton("Open again", kind: .quiet) { setup.install(app: model) }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.grailsDisplay(CGFloat(TypeScale.help))).foregroundStyle(Ink.canvas).frame(width: 20, height: 20).background(Ink.text, in: Circle())
            Text(text).font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The extension is asking to connect to Grails on this Mac.").font(.grailsBody(13)).foregroundStyle(Ink.text)
            GrailsButton("Allow", kind: .primary, identifier: "extension-allow") {
                if let r = model.pairRequest { model.allowPairing(r) }
            }
            .keyboardShortcut(.defaultAction)
            GrailsButton("Not now", kind: .quiet) { if let r = model.pairRequest { model.denyPairing(r) } }
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StatusDot(.ok)
                Text("Pinterest boards now import in full.").font(.grailsBody(13)).foregroundStyle(Ink.text)
            }
            GrailsButton("Done", kind: .primary, identifier: "extension-done") { setup.close() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// A browser to install into: its icon and name, ticked when chosen.
private struct BrowserTile: View {
    let browser: ChromiumBrowser
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        GrailsControl(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let icon = browser.icon { Image(decorative: icon, scale: 2).resizable() } else { InkWash(ink: Ink.fill) }
                }
                .frame(width: 36, height: 36)
                Text(browser.name).font(.grailsBody(12)).foregroundStyle(selected ? Ink.text : Ink.secondary).lineLimit(1)
            }
            .frame(width: 74, height: 78)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fill : (hovering ? Ink.fill.opacity(0.5) : Ink.clear)))
            .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(selected ? Ink.text : Ink.hairline, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark").font(ChromeFont.symbol(8, weight: .bold)).foregroundStyle(Ink.canvas)
                    .frame(width: 14, height: 14).background(Ink.text, in: Circle()).padding(4)
                    .grailsPop(selected)
            }
            .contentShape(Rectangle())
        }
        .hoverState($hovering)
        .accessibilityLabel(browser.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("extension-browser-\(browser.name.lowercased())")
    }
}

