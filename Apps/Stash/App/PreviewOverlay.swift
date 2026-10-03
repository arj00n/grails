import AppKit
import StashKit
import SwiftUI

/// Space / double-click preview: large image, ← → to step, Space or Esc to close.
struct PreviewOverlay: View {
    var model: AppModel
    let id: String
    @State private var image: NSImage?
    @FocusState private var focused: Bool

    private var summary: ItemSummary? { model.items.first { $0.id == id } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
                .onTapGesture { model.closePreview() }
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(40)
                    .shadow(radius: 20)
            } else {
                ProgressView().controlSize(.large)
            }
            VStack(spacing: 10) {
                Spacer()
                if let s = summary {
                    Text(s.name).font(.callout).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                    if s.kind == .link {
                        Button { model.openLinkInBrowser(s.id) } label: { Label("Open page", systemImage: "safari") }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("open-link")
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.escape) { model.closePreview(); return .handled }
        .onKeyPress(.space) { model.closePreview(); return .handled }
        .onKeyPress(.leftArrow) { model.stepPreview(-1); return .handled }
        .onKeyPress(.rightArrow) { model.stepPreview(1); return .handled }
        .task(id: id) { await load() }
        .accessibilityIdentifier("preview")
    }

    private func load() async {
        guard let s = summary, let layout = model.layout else { return }
        // Links show their snapshot (when chosen) or preview image; everything else its original file.
        let thumb = s.kind == .link && s.linkDisplay == "snapshot" ? layout.snapshotURL(s.id) : layout.thumbURL(s.id)
        let original = s.kind == .link ? nil : model.originalURL(for: s)
        image = s.kind == .link ? nil : ThumbnailLoader.shared.cached(id: s.id, pixels: 2048).map { NSImage(cgImage: $0, size: .zero) }
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            if let original, let hi = ThumbnailLoader.decode(original, maxPixel: 2400) { return hi }
            return ThumbnailLoader.decode(thumb, maxPixel: thumb.lastPathComponent == "snapshot.jpg" ? 1600 : 512)
        }.value
        if let cg, !Task.isCancelled { image = NSImage(cgImage: cg, size: .zero) }
    }
}
