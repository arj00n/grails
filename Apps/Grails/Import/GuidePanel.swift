import AppKit
import SwiftUI

/// What the floating guide shows: a short title, the steps in order (each pending, current or done), and optionally the extension's folder as
/// something to drag straight from the guide onto the browser's extensions page, so no Finder window is needed.
@MainActor @Observable
final class GuideModel {
    enum State { case pending, current, done }
    struct Step: Identifiable {
        let id = UUID()
        var text: String
        var state: State
    }

    var title = ""
    var steps: [Step] = []
    var folder: URL?
    /// A line that changes as things happen ("Scrolling 640").
    var status: String?
    var isShowing = false

    func set(title: String, steps: [(String, State)], folder: URL? = nil) {
        self.title = title
        self.steps = steps.map { Step(text: $0.0, state: $0.1) }
        self.folder = folder
        status = nil
    }

    /// Marks step `index` done and the next one current.
    func advance(to index: Int) {
        for i in steps.indices { steps[i].state = i < index ? .done : (i == index ? .current : .pending) }
    }

    func finishAll() { for i in steps.indices { steps[i].state = .done } }
}

/// A small panel above every other app (and every Space) that lists the exact steps while the person is in the browser, and follows them as
/// they happen. It never takes focus.
@MainActor
final class GuidePanelController {
    private var panel: NSPanel?
    let model: GuideModel
    var onClose: (() -> Void)?

    init(model: GuideModel) { self.model = model }

    func show() {
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
            let host = NSHostingView(rootView: GuideView(model: model, close: { [weak self] in self?.hide(); self?.onClose?() }))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host
            panel = p
        }
        guard let p = panel else { return }
        p.contentView?.layoutSubtreeIfNeeded()
        let fit = p.contentView?.fittingSize ?? NSSize(width: 320, height: 240)
        p.setContentSize(NSSize(width: 320, height: fit.height))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 320 - 16, y: f.maxY - p.frame.height - 16))
        }
        p.orderFrontRegardless()
        model.isShowing = true
    }

    /// Re-fits the panel to its content after the steps changed.
    func refit() {
        guard let p = panel, model.isShowing else { return }
        p.contentView?.layoutSubtreeIfNeeded()
        let fit = p.contentView?.fittingSize ?? p.frame.size
        let top = p.frame.maxY
        p.setContentSize(NSSize(width: 320, height: fit.height))
        p.setFrameOrigin(NSPoint(x: p.frame.minX, y: top - p.frame.height))
    }

    func hide() {
        panel?.orderOut(nil)
        model.isShowing = false
    }
}

struct GuideView: View {
    var model: GuideModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.title.uppercased()).font(.grailsDisplay(12)).foregroundStyle(Ink.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        marker(i + 1, step.state)
                        Text(step.text).font(.grailsBody(13)).foregroundStyle(step.state == .pending ? Ink.secondary : Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let folder = model.folder { FolderChip(url: folder) }
            if let status = model.status { Text(status).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
        .accessibilityIdentifier("guide-panel")
    }

    @ViewBuilder private func marker(_ n: Int, _ state: GuideModel.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.canvas)
                .frame(width: 18, height: 18).background(Ink.positive, in: Circle())
        case .current:
            Text("\(n)").font(.grailsDisplay(12)).foregroundStyle(Ink.canvas).frame(width: 18, height: 18).background(Ink.text, in: Circle())
        case .pending:
            Text("\(n)").font(.grailsDisplay(12)).foregroundStyle(Ink.secondary).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Ink.tertiary, lineWidth: 1))
        }
    }
}

/// The extension's folder, draggable from here onto the browser's extensions page.
private struct FolderChip: View {
    let url: URL
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Grails Extension").font(.grailsBody(13)).foregroundStyle(Ink.text)
                Text("Drag me onto the page").font(.grailsBody(11)).foregroundStyle(Ink.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .onDrag { NSItemProvider(object: url as NSURL) }
        .accessibilityIdentifier("guide-folder")
    }
}
