import GrailsDesign
import SwiftUI

/// A picture on the wall, and when it arrived (seconds on the wall's own clock) so it can fade in from grey.
struct Placed {
    var image: CGImage
    var at: Double
}

/// The wall, drawn for one moment: empty tiles in three greys, developed along the sweep, plus the pictures that have arrived.
/// Pure in its inputs, so a headless snapshot can ask for any moment.
struct MosaicCanvas: View {
    let slots: [Mosaic.Slot]
    /// Seconds since the screen appeared.
    let t: Double
    var centre: CGRect?
    var pictures: [Int: Placed] = [:]
    /// Tiles under the card beside the wall are not drawn.
    var reserved: CGRect?

    private let shades = [Ink.fill.opacity(0.55), Ink.fill, Ink.fillHover]
    private static let pictureFade = 0.18

    var body: some View {
        Canvas { context, _ in
            for s in slots {
                if let reserved, s.rect.intersects(reserved) { continue }
                let shape = Path(roundedRect: s.rect, cornerSize: CGSize(width: Ink.tileRadius, height: Ink.tileRadius), style: .continuous)
                context.fill(shape, with: .color(shades[s.shade].opacity(Mosaic.opacity(of: s, at: t, centre: centre))))
                guard let p = pictures[s.index] else { continue }
                let alpha = min(max((t - p.at) / Self.pictureFade, 0), 1)
                guard alpha > 0 else { continue }
                var layer = context
                layer.clip(to: shape)
                layer.opacity = alpha
                let w = CGFloat(p.image.width), h = CGFloat(p.image.height)
                let scale = max(s.rect.width / w, s.rect.height / h)
                let fit = CGRect(x: s.rect.midX - w * scale / 2, y: s.rect.midY - h * scale / 2, width: w * scale, height: h * scale)
                layer.draw(Image(decorative: p.image, scale: 1), in: fit)
            }
        }
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
    }
}

/// A clock for the wall, in seconds since it appeared. Stops when Reduce Motion is on, and shows the finished state.
struct WallClock<Content: View>: View {
    var reduceMotion = false
    var wall: WallModel?
    @ViewBuilder var content: (Double) -> Content
    @State private var origin = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 10 : timeline.date.timeIntervalSince(origin)
            content(t).onChange(of: t) { _, new in wall?.clock = new }
        }
        .onAppear { origin = Date(); wall?.clock = reduceMotion ? 10 : 0 }
    }
}

/// The pictures on the Arriving wall: each new item takes the free tile nearest its shape, at most six a second, so parallel
/// downloads never strobe. A full wall replaces its oldest pictures.
@MainActor @Observable
final class WallModel {
    private(set) var pictures: [Int: Placed] = [:]
    /// Seconds on the wall's clock; set by the view, read when a picture is placed.
    @ObservationIgnored var clock: Double = 0
    @ObservationIgnored private var slots: [Mosaic.Slot] = []
    @ObservationIgnored private var reserved: CGRect?
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var waiting: [(CGImage, Double)] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func configure(slots: [Mosaic.Slot], reserved: CGRect?) { self.slots = slots; self.reserved = reserved; pictures = pictures.filter { p in slots.contains { $0.index == p.key } } }

    /// Watches the import's arrivals and places them.
    func run(app: AppModel, reduceMotion: Bool) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pull(app)
                if !self.waiting.isEmpty { self.place(self.waiting.removeFirst(), instant: reduceMotion) }
                try? await Task.sleep(for: .seconds(Mosaic.swapInterval(reduceMotion: reduceMotion)))
            }
        }
    }

    func stop() { task?.cancel() }

    private func pull(_ app: AppModel) {
        guard let layout = app.layout, waiting.count < 24 else { return }
        for id in app.importModel.arrivals where seen.insert(id).inserted {
            ThumbnailLoader.shared.load(id: id, thumb: layout.thumbURL(id), original: nil, pixels: 256) { [weak self] image in
                guard let image else { return }
                MainActor.assumeIsolated { self?.waiting.append((image, Double(image.width) / Double(max(image.height, 1)))) }
            }
            if waiting.count >= 24 { break }
        }
    }

    /// For snapshots: puts a picture on the wall as if it had just arrived.
    func place(_ entry: (CGImage, Double), instant: Bool = false) {
        let usable = slots.filter { s in reserved.map { !s.rect.intersects($0) } ?? true }
        guard !usable.isEmpty else { return }
        let free = usable.filter { pictures[$0.index] == nil }
        let slot: Mosaic.Slot
        if let s = Mosaic.assign(aspect: entry.1, free: free) { slot = s }
        else if let oldest = usable.min(by: { (pictures[$0.index]?.at ?? 0) < (pictures[$1.index]?.at ?? 0) }) { slot = oldest }
        else { return }
        pictures[slot.index] = Placed(image: entry.0, at: instant ? -10 : clock)
    }
}
