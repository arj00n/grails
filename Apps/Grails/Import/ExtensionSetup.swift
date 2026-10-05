import AppKit
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
    /// The extension's page in the Chrome Web Store. Once it is listed, setup is: choose browsers, click Install, then the store's own Add
    /// button. Until then the extension goes in unpacked (its folder is copied somewhere stable, and the browser's extensions page opens).
    static var storeURL: URL? {
        if let s = UserDefaults.standard.string(forKey: "extensionStoreURL"), let u = URL(string: s) { return u }
        return nil
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

    var unpacked: Bool { ExtensionInstall.storeURL == nil }
    var chosen: [ChromiumBrowser] { browsers.filter { selected.contains($0.id) } }

    func open(continueImport: Bool = false) {
        browsers = ChromiumBrowser.installed()
        self.continueImport = continueImport
        opened = false
        connected = false
        let def = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { url in browsers.first { $0.url == url } }
        selected = Set([def ?? browsers.first].compactMap { $0?.id })
        isOpen = true
    }

    func close() { isOpen = false }

    func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }

    /// For the demo: a fixed set of browsers and a state to show.
    func demo(browsers: [ChromiumBrowser], selected: Set<String>, opened: Bool, connected: Bool = false) {
        self.browsers = browsers; self.selected = selected; self.opened = opened; self.connected = connected; isOpen = true
    }

    /// Opens the extension's page in each chosen browser: the store listing, or (until there is one) the extensions page, with the
    /// extension's folder copied somewhere stable and shown in Finder to drag in.
    func install(app: AppModel) {
        let targets = chosen
        guard !targets.isEmpty else { return }
        if let store = ExtensionInstall.storeURL {
            for b in targets { NSWorkspace.shared.open([store], withApplicationAt: b.url, configuration: NSWorkspace.OpenConfiguration()) }
        } else {
            guard let folder = app.copyExtensionFolder() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            for b in targets { NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: b.url, configuration: NSWorkspace.OpenConfiguration()) }
        }
        opened = true
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
        ZStack {
            Ink.canvas.opacity(0.7).ignoresSafeArea().onTapGesture { setup.close() }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(heading).font(.grailsDisplay(16)).foregroundStyle(Ink.text)
                    Spacer()
                    BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "extension-close") { setup.close() }
                }
                switch stage {
                case .choose: choose
                case .waiting: waiting
                case .allow: allow
                case .connected: connected
                }
                Button("") { setup.close() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
            }
            .padding(24)
            .frame(width: 460)
            .surfaceCard()
        }
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
                Text("No Chromium browser found. Install Chrome, Arc, Brave or Edge first.").font(.grailsBody(12)).foregroundStyle(Ink.destructive)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install in").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                    HStack(spacing: 8) { ForEach(setup.browsers) { b in BrowserTile(browser: b, selected: setup.selected.contains(b.id)) { setup.toggle(b.id) } } }
                }
            }
            VStack(spacing: 8) {
                Button { setup.install(app: model) } label: {
                    Text(installLabel).font(.grailsBody(15, bold: true)).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(BigPrimaryStyle()).disabled(setup.chosen.isEmpty)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("extension-install")
                Button("Not now") { setup.close() }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity)
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
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Ink.secondary).frame(width: 18)
            Text(text).font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: After Install

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                step(1, setup.unpacked ? "Turn on Developer mode, then drag the Extension folder onto the page" : "Click Add to \(setup.chosen.first?.name ?? "Chrome") in the tab that opened")
                step(2, "Come back here and click Allow")
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the extension").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                Spacer()
                Button("Open again") { setup.install(app: model) }.buttonStyle(.plain).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.grailsDisplay(12)).foregroundStyle(Ink.canvas).frame(width: 20, height: 20).background(Ink.text, in: Circle())
            Text(text).font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The extension is asking to connect to Grails on this Mac.").font(.grailsBody(13)).foregroundStyle(Ink.text)
            Button { if let r = model.pairRequest { model.allowPairing(r) } } label: {
                Text("Allow").font(.grailsBody(15, bold: true)).frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(BigPrimaryStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("extension-allow")
            Button("Not now") { if let r = model.pairRequest { model.denyPairing(r) } }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle").font(.system(size: 16)).foregroundStyle(Ink.positive)
                Text("Pinterest boards now import in full.").font(.grailsBody(13)).foregroundStyle(Ink.text)
            }
            Button { setup.close() } label: { Text("Done").font(.grailsBody(15, bold: true)).frame(maxWidth: .infinity).frame(height: 44) }
                .buttonStyle(BigPrimaryStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("extension-done")
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
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let icon = browser.icon { Image(decorative: icon, scale: 2).resizable() } else { Ink.fill }
                }
                .frame(width: 36, height: 36)
                Text(browser.name).font(.grailsBody(12)).foregroundStyle(selected ? Ink.text : Ink.secondary).lineLimit(1)
            }
            .frame(width: 74, height: 78)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fill : (hovering ? Ink.fill.opacity(0.5) : .clear)))
            .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(selected ? Ink.text : Ink.hairline, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.canvas)
                        .frame(width: 14, height: 14).background(Ink.text, in: Circle()).padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(browser.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("extension-browser-\(browser.name.lowercased())")
    }
}

/// The big call to action: the one filled button, tall, across the card.
struct BigPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Ink.canvas)
            .background(Ink.text.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.25), in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
    }
}
