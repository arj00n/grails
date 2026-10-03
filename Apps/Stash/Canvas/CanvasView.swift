import AppKit
import StashKit
import SwiftUI

/// SwiftUI host for the canvas. Items, placements, selection and one-shot requests flow in from the model;
/// edits flow back through `commitCanvas` (which records undo and saves to the library).
struct CanvasView: NSViewRepresentable {
    var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let v = CanvasNSView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        container.addSubview(v)
        context.coordinator.canvas = v
        context.coordinator.hitch = HitchMonitor.make()
        if let probe = context.coordinator.hitch?.probe {
            probe.frame = NSRect(x: 0, y: 0, width: 2, height: 2)
            probe.alphaValue = 0.02
            container.addSubview(probe)
        }
        context.coordinator.hitch?.start(on: v)
        v.onSelectionChange = { [weak model] ids in model?.selection = ids }
        v.onCommit = { [weak model] updates, label in model?.commitCanvas(updates, label: label) }
        v.onPreview = { [weak model] id in model?.openPreview(id) }
        v.onPaste = { [weak model] in model?.paste() }
        v.onOptionClick = { [weak model] id in model?.toggleLike(ids: [id]) }
        v.onViewportSettled = { [weak model] key, origin, scale in CanvasViewports.save(key: CanvasViewports.scoped(key, model?.layout), origin: origin, scale: scale) }
        v.keyHandler = { [weak model] event in
            guard let model, let action = ShortcutStore.shared.action(for: event, plainOnly: true) else { return false }
            model.run(action)
            return true
        }
        v.contextMenuProvider = { [weak model] id in
            guard let model, let s = model.summary(id) else { return nil }
            return model.itemContextMenu(anchor: s, canvas: true)
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let c = context.coordinator
        guard let v = c.canvas else { return }
        if v.frame.size != container.bounds.size { v.frame = container.bounds }
        v.layout = model.layout
        if c.itemsVersion != model.itemsVersion {
            c.itemsVersion = model.itemsVersion
            v.setItems(model.items)
        }
        if c.canvasVersion != model.canvasVersion {
            c.canvasVersion = model.canvasVersion
            let key = model.canvasBoardKey
            v.setPlacements(model.canvasPlacements, boardKey: key, savedViewport: key.flatMap { CanvasViewports.load(key: CanvasViewports.scoped($0, model.layout)) })
        }
        v.setSelection(model.selection)
        if !c.benchStarted, ProcessInfo.processInfo.environment["STASH_BENCH"] != nil, !model.canvasPlacements.isEmpty {
            c.benchStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak v, weak c] in MainActor.assumeIsolated { v?.startBenchmark(hitch: c?.hitch) } }
        }
        if let r = model.canvasRequest, r.id != c.lastRequest {
            c.lastRequest = r.id
            switch r.kind {
            case .fit: v.fit(ids: nil, animated: true)
            case .fitSelection: v.fit(ids: Array(model.selection), animated: true)
            case .reveal(let ids): v.fit(ids: ids, animated: true, margin: 110)
            case .zoom(let f): v.zoom(by: f, at: CGPoint(x: v.bounds.midX, y: v.bounds.midY))
            }
        }
        if c.focusTick != model.focusGridTick {
            c.focusTick = model.focusGridTick
            v.window?.makeFirstResponder(v)
        }
    }

    final class Coordinator {
        weak var canvas: CanvasNSView?
        var hitch: HitchMonitor?
        var benchStarted = false
        var itemsVersion = -1
        var canvasVersion = -1
        var lastRequest: UUID?
        var focusTick = 0
    }
}

/// Where you were looking on each board. Local to this Mac (a viewport isn't something to sync).
enum CanvasViewports {
    /// Board keys repeat across libraries ("library", "inbox"), so the saved view is scoped to the library's location.
    static func scoped(_ key: String, _ layout: LibraryLayout?) -> String { "\(layout?.root.path ?? "")#\(key)" }

    static func save(key: String, origin: CGPoint, scale: CGFloat) {
        UserDefaults.standard.set([Double(origin.x), Double(origin.y), Double(scale)], forKey: "canvasViewport.\(key)")
    }

    static func load(key: String) -> (CGPoint, CGFloat)? {
        guard let a = UserDefaults.standard.array(forKey: "canvasViewport.\(key)") as? [Double], a.count == 3, a[2] > 0 else { return nil }
        return (CGPoint(x: a[0], y: a[1]), CGFloat(a[2]))
    }
}
