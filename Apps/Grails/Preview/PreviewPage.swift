import GrailsKit
import GrailsDesign
import SwiftUI

/// What the stage tells the page while a finger is closing it: the page and the information fade together.
@MainActor @Observable
final class PreviewChrome {
    var dismiss = 0.0
    /// 0 while the picture is still on its tile, 1 once it is in place.
    var flight = 1.0
    /// The picture is flying back onto its tile. The details stay hidden until that return is gone.
    var returningToTile = false
}

/// The preview is a page: the picture on the left, everything about it in the info column on the right (shown or hidden from
/// the bar, and remembered). Swipe sideways for the next one, up or down to close.
struct PreviewPage: View {
    var model: AppModel
    @State private var chrome: PreviewChrome

    init(model: AppModel) {
        self.model = model
        let chrome = PreviewChrome()
        // the page starts transparent when the picture is about to fly out of its tile
        if model.tileGeometry != nil, !ReduceMotion.isOn { chrome.flight = 0 }
        _chrome = State(initialValue: chrome)
    }

    private var position: Int? { model.previewID.flatMap { model.previewSet?.position(of: $0) } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            InkWash(ink: Ink.canvas.opacity(chrome.flight * (1 - chrome.dismiss * 0.9))).ignoresSafeArea()
            // the stage draws above the column: a picture flying to or from a tile on the right passes over it
            GrailsInfoSplit(isOpen: model.showPreviewInfo, panelOpacity: infoOpacity) {
                PreviewStage(model: model, chrome: chrome)
            } panel: {
                column
            }
            strip.opacity(infoOpacity)
        }
        .onChange(of: model.itemsVersion) { model.refreshPreviewSet() }
        .accessibilityIdentifier("preview")
    }

    private var infoOpacity: Double {
        PreviewInfoFade.opacity(flight: chrome.flight, dismiss: chrome.dismiss, returningToTile: chrome.returningToTile)
    }

    private var strip: some View {
        HStack(spacing: 6) {
            BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "preview-close") { model.closePreview() }
            if let p = position, let n = model.previewSet?.count {
                Text("\(p + 1) / \(n)").font(.grailsBody(13)).monospacedDigit().foregroundStyle(Ink.secondary)
                Text("· \(model.title)").font(.grailsBody(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            Spacer()
            if let id = model.previewID {
                BarButton(symbol: "square.on.square", help: "Find Similar", identifier: "preview-similar") { model.findSimilar(to: id) }
            }
            PreviewShareMenu(model: model)
            BarButton(symbol: "sidebar.right", selected: model.showPreviewInfo, help: "Show or hide details", identifier: "preview-info") {
                model.toggleFullscreenInfo()
            }
            .padding(.trailing, 8)
        }
        .padding(.leading, TrafficLightMetrics.shared.leading)
        .frame(height: RootView.barHeight)
    }

    private var column: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InfoBlock(model: model, itemID: model.previewID)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        // the column runs under the bar like the sidebar; its contents start below the bar
        .padding(.top, RootView.barHeight)
        .accessibilityIdentifier("preview-details")
    }
}

/// Export or share this one item: the same two formats as the bar, scoped to what's on screen.
struct PreviewShareMenu: View {
    var model: AppModel

    var body: some View {
        GrailsMenu {
            GrailsControl("Export as HTML…") { export(.html) }
            GrailsControl("Export as PDF…") { export(.pdf) }
            Divider()
            GrailsControl("Copy Link") { if let id = model.previewID { model.copyLink(.item(id)) } }
            if let id = model.previewID, let s = model.previewSet?.position(of: id).flatMap({ model.previewSet?[$0] }), s.kind == .link {
                GrailsControl("Open Page") { model.openLinkInBrowser(s.id) }
            }
        } label: {
            BarIcon(symbol: "square.and.arrow.up")
        }
        .help("Export or share")
        .accessibilityLabel("Export or share")
        .accessibilityIdentifier("preview-share")
    }

    private func export(_ format: ShareFormat) {
        guard let id = model.previewID else { return }
        model.selection = [id]
        model.exportWebPage(selectionOnly: true, format: format)
    }
}

/// Bridges the stage into SwiftUI: hands it the set and where to start, and hears back only about committed changes.
struct PreviewStage: NSViewRepresentable {
    var model: AppModel
    var chrome: PreviewChrome

    func makeNSView(context: Context) -> PreviewStageView {
        let v = PreviewStageView()
        // the stage runs under the bar; pictures fit below it, like the sidebar's and the info column's contents
        v.topInset = RootView.barHeight
        v.sourceFor = { [weak model] s in model?.previewSource(for: s) ?? PreviewSource(original: nil, thumb: URL(fileURLWithPath: "/"), thumbMax: 512) }
        v.onCommit = { [weak model] i in model?.commitPreview(position: i) }
        v.onClose = { [weak model] in model?.closePreview() }
        v.onDismissProgress = { [weak chrome] p in if chrome?.dismiss != p { chrome?.dismiss = p } }
        v.onFlight = { [weak chrome] f in if chrome?.flight != f { chrome?.flight = f } }
        v.onReturnToTile = { [weak chrome, weak model] in
            chrome?.returningToTile = true
            model?.holdInfoClosedForPreviewReturn()
        }
        v.tileRectProvider = model.tileGeometry == nil ? nil : { [weak model] id in model?.tileGeometry?.rect(id) }
        v.tileHide = { [weak model] id, hidden in model?.tileGeometry?.hide(id, hidden) }
        v.onOpenSource = { [weak model] in model?.openPreviewSource() }
        v.keyHandler = { [weak model] event in
            guard let model, let action = ShortcutStore.shared.action(for: event, plainOnly: true) else { return false }
            model.run(action)
            return true
        }
        if let set = model.previewSet, let id = model.previewID, let pos = set.position(of: id) {
            v.load(set, at: pos, animatedOpen: true)
            context.coordinator.version = model.previewSetVersion
        }
        // if the flight never got going, don't leave the page invisible
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak v] in if v?.isWaitingToOpen == true { v?.forceOpen() } }
        if let dir = ProcessInfo.processInfo.environment["GRAILS_PREVIEW_DEMO"] { v.runDemo(into: dir) }
        return v
    }

    func updateNSView(_ v: PreviewStageView, context: Context) {
        guard let set = model.previewSet, let id = model.previewID else { return }
        if context.coordinator.version != model.previewSetVersion {
            context.coordinator.version = model.previewSetVersion
            v.replaceSet(set, position: set.position(of: id) ?? 0)
        } else if v.currentID != id, let pos = set.position(of: id) {
            v.jump(to: pos)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var version = -1 }
}
