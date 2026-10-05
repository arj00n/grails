import GrailsDesign
import GrailsKit
import SwiftUI

/// The picture grid on the Arriving screen: tiles only ever get added, each in the shortest column at that moment, so no tile that is already
/// on screen ever moves. A picture joins only once its thumbnail is decoded (so it appears whole, with no placeholder), and the pacer lets
/// at most a few in at a time. It never scrolls by itself.
@MainActor @Observable
final class ArrivalGridModel {
    struct Tile: Identifiable, Equatable {
        let id: String
        let aspect: CGFloat            // height / width
    }

    private(set) var columns: [[Tile]] = []
    private(set) var count = 0
    /// Whether the visible part is already full (new pictures land below the fold).
    private(set) var viewportFull = false

    @ObservationIgnored private var heights: [CGFloat] = []
    @ObservationIgnored private var pacer: ArrivalPacer
    @ObservationIgnored private var requested = Set<String>()
    @ObservationIgnored private var ready: [String: CGFloat] = [:]
    @ObservationIgnored private var all: [Tile] = []
    @ObservationIgnored private var columnWidth: CGFloat = 170
    @ObservationIgnored private var viewport: CGFloat = 800
    @ObservationIgnored private var task: Task<Void, Never>?
    let gap: CGFloat = 8
    static let minColumnWidth: CGFloat = 150

    init(reduceMotion: Bool) { pacer = ArrivalPacer(reduceMotion: reduceMotion) }

    /// The width available decides the column count; changing it relays out once (the window was resized).
    func configure(width: CGFloat, height: CGFloat) {
        viewport = height
        let n = max(Int((width + gap) / (Self.minColumnWidth + gap)), 1)
        let w = (width - CGFloat(n - 1) * gap) / CGFloat(n)
        guard n != columns.count || abs(w - columnWidth) > 0.5 else { return }
        columnWidth = w
        columns = Array(repeating: [], count: n)
        heights = Array(repeating: 0, count: n)
        for t in all { place(t) }
        viewportFull = heights.min() ?? 0 >= viewport
    }

    private func place(_ t: Tile) {
        let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
        columns[c].append(t)
        heights[c] += columnWidth * t.aspect + gap
    }

    /// Runs the pacing loop, watching the import's arrivals.
    func run(app: AppModel) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pull(app)
                self.releaseNext()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func stop() { task?.cancel() }

    private func pull(_ app: AppModel) {
        guard let layout = app.layout else { return }
        for id in app.importModel.arrivals where requested.insert(id).inserted {
            ThumbnailLoader.shared.load(id: id, thumb: layout.thumbURL(id), original: nil, pixels: 512) { [weak self] image in
                guard let image else { return }
                MainActor.assumeIsolated { self?.thumbnailReady(id, CGFloat(image.height) / CGFloat(max(image.width, 1))) }
            }
        }
    }

    private func thumbnailReady(_ id: String, _ aspect: CGFloat) {
        ready[id] = aspect
        pacer.enqueue([id])
    }

    private func releaseNext() {
        pacer.viewportFull = viewportFull
        let batch = pacer.release(at: ProcessInfo.processInfo.systemUptime)
        guard !batch.isEmpty else { return }
        for id in batch {
            let t = Tile(id: id, aspect: ready[id] ?? 1)
            all.append(t)
            if !columns.isEmpty { place(t) }
        }
        count = all.count
        viewportFull = (heights.min() ?? 0) >= viewport
    }
}

struct ArrivalGrid: View {
    var model: ArrivalGridModel
    var app: AppModel
    /// Dev snapshots (ImageRenderer) can't draw a scroll view's contents: the demo asks for the columns laid out plainly.
    private static let plain = ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_DEMO"] != nil

    private var columns: some View {
        HStack(alignment: .top, spacing: model.gap) {
            ForEach(model.columns.indices, id: \.self) { c in
                LazyVStack(spacing: model.gap) {
                    ForEach(model.columns[c]) { ArrivalTile(tile: $0, app: app) }
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if Self.plain { columns.frame(maxHeight: .infinity, alignment: .top).clipped() }
                else { ScrollView(.vertical, showsIndicators: false) { columns.padding(.bottom, 24) } }
            }
            .onAppear { model.configure(width: geo.size.width, height: geo.size.height) }
            .onChange(of: geo.size) { model.configure(width: geo.size.width, height: geo.size.height) }
        }
        .accessibilityIdentifier("arrival-grid")
    }
}

private struct ArrivalTile: View {
    let tile: ArrivalGridModel.Tile
    var app: AppModel
    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(1 / tile.aspect, contentMode: .fit)
            .overlay {
                // a decoded thumbnail is in the cache before the tile exists, so it shows whole from its first frame
                if let img = image ?? ThumbnailLoader.shared.cached(id: tile.id, pixels: 512) { Image(decorative: img, scale: 1).resizable().scaledToFill() } else { Ink.fill }
            }
            .clipShape(RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous))
            .onAppear {
                guard image == nil, let layout = app.layout else { return }
                if let hit = ThumbnailLoader.shared.cached(id: tile.id, pixels: 512) { image = hit; return }
                ThumbnailLoader.shared.load(id: tile.id, thumb: layout.thumbURL(tile.id), original: nil, pixels: 512) { img in MainActor.assumeIsolated { image = img } }
            }
    }
}
