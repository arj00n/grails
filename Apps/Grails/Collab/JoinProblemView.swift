import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// An invite link whose library this Mac can't find: what it looks like (no Drive, not signed in, another account, not shared yet), the
/// steps, one main action, and a reply to the owner. It looks again by itself every few seconds and opens the library once it's there.
struct JoinProblemView: View {
    var model: AppModel
    var state: JoinState

    private var c: CollabModel { model.collab }
    static let width: CGFloat = 520

    var body: some View {
        let copy = state.copy
        VStack(alignment: .leading, spacing: 18) {
            CollabHeader(title: state.name) { c.closeJoin(state, resolving: false) }
            Text(copy.title).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text)
                .accessibilityIdentifier("join-problem-\(copy.primary.rawValue)")
            StepsList(copy.steps)
            HStack(spacing: 6) {
                Circle().fill(state.checking ? Ink.text : Ink.secondary).frame(width: 5, height: 5)
                Text(state.checking ? "Looking…" : "Looks again by itself").font(.grailsBody(11)).foregroundStyle(Ink.secondary)
                Button("Check now") { c.perform(.checkAgain, state) }.buttonStyle(.plain).font(.grailsBody(11)).foregroundStyle(Ink.text)
                    .accessibilityIdentifier("join-checkAgain")
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            HStack(spacing: 16) {
                ForEach(copy.secondary.filter { $0 != .checkAgain }, id: \.self) { a in secondary(a) }
                Spacer()
                primary(copy.primary)
            }
            Button("") { c.closeJoin(state, resolving: false) }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("join-problem")
    }

    @ViewBuilder private func primary(_ a: JoinAction) -> some View {
        if a == .askForAccess {
            askLink { Text(a.label) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        } else {
            Button(a.label) { c.perform(a, state) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("join-\(a.rawValue)")
        }
    }

    @ViewBuilder private func secondary(_ a: JoinAction) -> some View {
        if a == .askForAccess {
            askLink { Text(a.label) }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
        } else {
            QuietButton(title: a.label, identifier: "join-\(a.rawValue)") { c.perform(a, state) }
        }
    }

    /// "Ask for access": the share sheet (Mail, Messages…) with the request filled in, and the same words on the clipboard for any chat.
    private func askLink<L: View>(@ViewBuilder label: () -> L) -> some View {
        let r = state.request
        return ShareLink(item: r.body, subject: Text(r.subject), message: Text(""), label: label)
            .simultaneousGesture(TapGesture().onEnded { c.copyRequest(state) })
            .accessibilityIdentifier("join-askForAccess")
    }
}

/// The join checklist above every other app, only while Grails itself is not in front. It never takes focus, so Drive or Settings stays where it is.
@MainActor
final class JoinFloat {
    private var panel: NSPanel?
    private var observers: [any NSObjectProtocol] = []
    private var state: JoinState?
    private var placed = false
    /// Closed by hand: stay away until Grails is in front again, then the next time it isn't.
    private var hiddenUntilReturn = false

    var isVisible: Bool { panel?.isVisible == true }

    func arm(_ state: JoinState) {
        disarm()
        self.state = state
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    func disarm() {
        hide()
        state = nil
        placed = false
        hiddenUntilReturn = false
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        panel?.close()
        panel = nil
    }

    func show() {
        guard let state, !hiddenUntilReturn else { return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let host = NSHostingView(rootView: JoinFloatView(state: state, close: { [weak self] in self?.close() }))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host
            panel = p
        }
        guard let p = panel else { return }
        p.contentView?.layoutSubtreeIfNeeded()
        let fit = p.contentView?.fittingSize ?? NSSize(width: 320, height: 240)
        let bottom: CGFloat? = placed ? p.frame.minY : nil
        p.setContentSize(NSSize(width: 320, height: max(fit.height, 1)))
        if let bottom {
            p.setFrameOrigin(NSPoint(x: p.frame.minX, y: bottom))
        } else if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.minX + 16, y: f.minY + 16))
            placed = true
        }
        p.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        hiddenUntilReturn = false
    }

    func refit() {
        guard isVisible else { return }
        show()
    }

    private func close() {
        panel?.orderOut(nil)
        hiddenUntilReturn = true
    }
}

/// The checklist, small enough to sit in a corner while the steps happen in another app.
private struct JoinFloatView: View {
    var state: JoinState
    var close: () -> Void

    var body: some View {
        let copy = state.copy
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(state.name.uppercased()).font(.grailsDisplay(12)).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            Text(copy.title).font(.grailsBody(13, bold: true)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            StepsList(copy.steps)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
        .accessibilityIdentifier("join-float")
    }
}
