import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Shows a collab screen as a sheet on the library window, so it works the same from the sidebar menu, Settings and an incoming link.
@MainActor
final class CollabSheet {
    private var window: NSWindow?

    var isShowing: Bool { window != nil }

    /// False when there is no library window to attach to (headless runs, or while every window is closed).
    @discardableResult
    func present<V: View>(_ view: V) -> Bool {
        guard let parent = Self.hostWindow() else { return false }
        dismiss()
        let host = NSHostingController(rootView: view.background(Ink.surface))
        host.sizingOptions = .preferredContentSize
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = .ink(.surface)
        w.appearance = parent.appearance
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        parent.makeKeyAndOrderFront(nil)
        parent.beginSheet(w)
        window = w
        return true
    }

    func dismiss() {
        guard let w = window else { return }
        window = nil
        if let parent = w.sheetParent { parent.endSheet(w) } else { w.orderOut(nil) }
    }

    /// The library window: not Settings, not a panel, not already a sheet.
    static func hostWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter {
            $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil && $0.canBecomeMain && $0.identifier?.rawValue.contains("Settings") != true
        }
        if let m = NSApp.mainWindow, candidates.contains(m) { return m }
        return candidates.first
    }
}

// MARK: Pieces shared by the set-up, invite and join screens

private struct StillKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Set by the headless demo: `ImageRenderer` can't draw AppKit-backed controls (text fields, menus), so they draw as plain text.
    var collabStill: Bool {
        get { self[StillKey.self] }
        set { self[StillKey.self] = newValue }
    }
}

/// A menu behind a label; in a still picture, just the label.
struct CollabMenu<Items: View, Label: View>: View {
    @ViewBuilder var items: Items
    @ViewBuilder var label: Label
    @Environment(\.collabStill) private var still

    var body: some View {
        if still { label } else { Menu { items } label: { label }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize() }
    }
}

/// A tag at the end of a row ("Recommended", "Library"): outlined, so it reads on a selected row too.
struct RowTag: View {
    let text: String
    var body: some View {
        Text(text).font(.grailsBody(11)).foregroundStyle(Ink.secondary).padding(.horizontal, 6).frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
    }
}

/// The second kind of button: outlined, for an action next to the screen's one filled button.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grailsBody(13))
            .foregroundStyle(Ink.text.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, 12).frame(height: 28)
            .background(configuration.isPressed ? Ink.fill : Color.clear, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
    }
}

/// The screen's title (VCR, 16) with a close button at the right.
struct CollabHeader: View {
    let title: String
    var close: (() -> Void)?

    var body: some View {
        HStack {
            Text(title.uppercased()).font(.grailsDisplay(16)).foregroundStyle(Ink.text).lineLimit(1)
            Spacer()
            if let close { BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "collab-close", action: close) }
        }
        .frame(height: 28)
    }
}

/// Where you are in the set-up: the five steps in a row, the current one in `text`.
struct StepStrip: View {
    let current: CollabSetupFlow.Step

    var body: some View {
        let steps = CollabSetupFlow.strip
        let at = steps.firstIndex(of: current) ?? steps.count
        HStack(spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 5) {
                    Group {
                        if i < at { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                        else { Text("\(i + 1)").font(.grailsBody(10)) }
                    }
                    .foregroundStyle(i == at ? Ink.canvas : Ink.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(i == at ? Ink.text : Ink.fill))
                    Text(s.label).font(.grailsBody(12)).foregroundStyle(i == at ? Ink.text : Ink.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(min(at + 1, steps.count)) of \(steps.count), \(current.label)")
    }
}

/// A choice in a list: a radio, a title, a quiet detail and an optional tag ("Recommended").
struct ChoiceRow: View {
    let selected: Bool
    let title: String
    var detail: String?
    var tag: String?
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Ink.text : Ink.secondary, lineWidth: 1).frame(width: 14, height: 14)
                    if selected { Circle().fill(Ink.text).frame(width: 6, height: 6) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.grailsBody(13)).foregroundStyle(enabled ? Ink.text : Ink.secondary).lineLimit(1)
                    if let detail { Text(detail).font(.grailsBody(11)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer(minLength: 8)
                if let tag { RowTag(text: tag) }
            }
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fill : (hovering ? Ink.fill.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .hoverState($hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Numbered steps the person takes outside Grails (in Drive, in Finder).
struct StepsList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.grailsBody(11)).foregroundStyle(Ink.canvas).frame(width: 18, height: 18).background(Ink.text, in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(s).font(.grailsBody(13)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A quiet box on the screen's surface: a situation and what to do about it.
struct NoticeBox<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.grailsBody(13, bold: true)).foregroundStyle(Ink.text)
                if let detail { Text(detail).font(.grailsBody(12)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
    }
}

/// A quiet text button (secondary actions).
struct QuietButton: View {
    let title: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(title, action: action).buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
            .accessibilityIdentifier(identifier ?? "collab-\(title.lowercased())")
    }
}

/// A plain text field on a `fill` background, as elsewhere in the app.
struct CollabField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat?
    var identifier: String
    var onSubmit: () -> Void = {}
    @Environment(\.collabStill) private var still

    var body: some View {
        Group {
            if still {
                Text(text.isEmpty ? placeholder : text).font(.grailsBody(13)).foregroundStyle(text.isEmpty ? Ink.secondary : Ink.text)
                    .lineLimit(1).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            } else {
                TextField(placeholder, text: $text).textFieldStyle(.plain).font(.grailsBody(13)).onSubmit(onSubmit)
            }
        }
        .padding(.horizontal, 10).frame(width: width, height: 30, alignment: .leading)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .accessibilityIdentifier(identifier)
    }
}

/// A check on the Check screen: ✓, waiting, ✕ or "can't tell".
struct CheckLine: View {
    let row: PlacementCheckRow

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch row.state {
                case .ok: Image(systemName: "checkmark").foregroundStyle(Ink.positive)
                case .waiting: Image(systemName: "clock").foregroundStyle(Ink.secondary)
                case .failed: Image(systemName: "xmark").foregroundStyle(Ink.destructive)
                case .unknown: Image(systemName: "minus").foregroundStyle(Ink.secondary)
                }
            }
            .font(.system(size: 11, weight: .semibold)).frame(width: 16)
            Text(row.label).font(.grailsBody(13)).foregroundStyle(Ink.text)
            Spacer()
            Text(stateLabel).font(.grailsBody(12)).foregroundStyle(row.state == .failed ? Ink.destructive : Ink.secondary)
        }
        .frame(height: 24)
    }

    private var stateLabel: String {
        switch row.state {
        case .ok: ""
        case .waiting: "Waiting"
        case .failed: "No"
        case .unknown: "Can't tell"
        }
    }
}

/// An issue under the checks: its title and its one line.
struct IssueLine: View {
    let issue: PlacementIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: issue.severity >= .warn ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 11)).foregroundStyle(issue.severity == .block ? Ink.destructive : (issue.severity == .warn ? Ink.alert : Ink.secondary)).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.grailsBody(13, bold: true)).foregroundStyle(Ink.text)
                Text(issue.detail).font(.grailsBody(12)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Where the screen's buttons sit: quiet ones on the left, the one primary action on the right.
struct ActionBar<Leading: View>: View {
    let primary: String
    var enabled = true
    var identifier: String
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 16) {
            leading
            Spacer()
            Button(primary, action: action).buttonStyle(PrimaryButtonStyle()).disabled(!enabled)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier(identifier)
        }
    }
}
