import AVKit
import AppKit
import GrailsKit
import SwiftUI

/// Space / double-click preview: large image, ← → to step, Space or Esc to close.
struct PreviewOverlay: View {
    var model: AppModel
    let id: String
    @State private var image: NSImage?
    @FocusState private var focused: Bool
    @State private var downloading = false
    @State private var detailsShown = false
    @State private var hideTask: Task<Void, Never>?

    private var summary: ItemSummary? { model.items.first { $0.id == id } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
                .onTapGesture { model.closePreview() }
            if let s = summary, s.kind == .video, let url = model.originalURL(for: s), FileManager.default.fileExists(atPath: url.path) {
                VideoPlayerView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
                    .padding(40)
                    .id(url)
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
                    .padding(40)
            } else {
                ProgressView().controlSize(.large)
            }
            if downloading {
                VStack { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Downloading original…").font(.callout) }
                    .padding(.horizontal, 14).padding(.vertical, 8).glassPill(); Spacer() }
                    .padding(.top, 24)
            }
            VStack(spacing: 10) {
                Spacer()
                if let s = summary {
                    Text(s.name).font(.callout).foregroundStyle(Ink.text)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassPill()
                    if s.kind == .link {
                        Button { model.openLinkInBrowser(s.id) } label: { Label("Open page", systemImage: "safari") }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("open-link")
                    }
                }
            }
            .padding(.bottom, 16)
            detailsEdge
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.escape) { model.closePreview(); return .handled }
        .onKeyPress(.space) { model.closePreview(); return .handled }
        .onKeyPress(.leftArrow) { model.stepPreview(-1); return .handled }
        .onKeyPress(.rightArrow) { model.stepPreview(1); return .handled }
        .onKeyPress(KeyEquivalent("i")) { withAnimation(.smooth(duration: 0.22)) { detailsShown.toggle() }; return .handled }
        .task(id: id) { await load() }
        .accessibilityIdentifier("preview")
    }

    // MARK: Details that slide in from the right edge

    /// Move the pointer to the right edge (or press I) and the item's details slide in; leave the panel and they slide away.
    @ViewBuilder private var detailsEdge: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: 40).contentShape(Rectangle())
                    .onHover { if $0 { showDetails() } }
                if !detailsShown {
                    Capsule().fill(Ink.tertiary).frame(width: 4, height: 54).padding(.trailing, 9).allowsHitTesting(false)
                }
            }
        }
        if detailsShown {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ScrollView {
                    ItemDetails(model: model, itemID: id, showsPicture: false)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(width: 340)
                .glassCard()
                .padding(12)
                .onHover { inside in if inside { hideTask?.cancel() } else { scheduleHide() } }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityIdentifier("preview-details")
            }
        }
    }

    private func showDetails() {
        hideTask?.cancel()
        guard !detailsShown else { return }
        withAnimation(.smooth(duration: 0.22)) { detailsShown = true }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.22)) { detailsShown = false }
        }
    }

    private func load() async {
        guard let s = summary, let layout = model.layout else { return }
        // Links show their snapshot (when chosen) or preview image; everything else its original file.
        let thumb = s.kind == .link && s.linkDisplay == "snapshot" ? layout.snapshotURL(s.id) : layout.thumbURL(s.id)
        let original = s.kind == .link ? nil : model.originalURL(for: s)
        image = s.kind == .link ? nil : ThumbnailLoader.shared.cached(id: s.id, pixels: 2048).map { NSImage(cgImage: $0, size: .zero) }
        // Reading a File Provider placeholder makes the sync client download it; show the thumbnail and a note meanwhile.
        let placeholder = original.map { FileAvailability.of($0) == .cloudOnly } ?? false
        if let original, placeholder { FileAvailability.requestDownload(original) }
        downloading = placeholder
        defer { downloading = false }
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            if let original, let hi = ThumbnailLoader.decode(original, maxPixel: 2400) { return hi }
            return ThumbnailLoader.decode(thumb, maxPixel: thumb.lastPathComponent == "snapshot.jpg" ? 1600 : 512)
        }.value
        if let cg, !Task.isCancelled { image = NSImage(cgImage: cg, size: .zero) }
    }
}


/// A video in the preview: plays right away, with the standard controls.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let v = NonFocusingPlayerView()
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = false
        let player = AVPlayer(url: url)
        v.player = player
        player.play()
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause(); v.player = nil }

    /// Keeps the keyboard with the preview overlay, so Space and Esc still close it and ← → still step.
    private final class NonFocusingPlayerView: AVPlayerView {
        override var acceptsFirstResponder: Bool { false }
    }
}
