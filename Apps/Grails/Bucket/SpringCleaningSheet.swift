import AppKit
import AVFoundation
import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI

struct SpringCleaningSheet: View {
    @Bindable var model: AppModel
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @State private var drag: Double = 0
    @State private var lift: Double = 0
    @State private var frontOpacity: Double = 1
    @State private var cardWidth: Double = 320
    @State private var busy = false
    @State private var pending: SpringChoice?
    @State private var focusToken = 0

    private var allowed: Bool { SpringAccess.allows(model.bucket.role) }

    var body: some View {
        GrailsModal(title: SpringCommand.title, step: "spring", identifier: "spring-cleaning", onClose: { model.bucket.showSpring = false }) {
            deck
        } footer: {
            HStack {
                GrailsButton("Chuck", kind: .secondary, identifier: "spring-chuck", enabled: canAct) { finish(.chuck) }
                Spacer()
                GrailsButton("Keep", kind: .primary, identifier: "spring-keep", enabled: canAct) { finish(.keep) }
            }
        }
        .frame(minWidth: CGFloat(ModalMetrics.width), minHeight: model.bucket.deck.current == nil ? 0 : SpringSheetLayout.minimumHeight, alignment: .top)
        .task {
            guard ProcessInfo.processInfo.environment["GRAILS_SCREEN"] != "spring" else { return }
            await model.bucket.refreshDeck()
        }
    }

    private var canAct: Bool { model.bucket.deck.current != nil && allowed && !busy }

    /// Every card is this square. It is the modal body width, so the picture cannot grow the sheet.
    private var cardSide: CGFloat { SpringSheetLayout.cardSide }

    private var deck: some View {
        let side = cardSide
        let cards = Array(model.bucket.deck.cards.prefix(3))
        return Group {
            if cards.isEmpty {
                Text("All tidy. Nothing to clean up.")
                    .font(.grailsBody(13))
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 72)
            } else {
                ZStack(alignment: .top) {
                    ForEach(Array(cards.enumerated().reversed()), id: \.element.key) { index, card in
                        let depth = index
                        face(
                            card,
                            playing: depth == 0 && !busy && SpringMedia.plays(card),
                            showsPlayer: depth < 2 && SpringMedia.plays(card),
                            side: side
                        )
                        .frame(width: side, height: side)
                        .clipped()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SpringMedia.plays(card) ? "Video" : "Image")
                        .accessibilityIdentifier(depth == 0 ? "spring-card" : "spring-back")
                        .scaleEffect(CGFloat(SpringFlight.scale(depth: depth, lift: lift)), anchor: .bottom)
                        .offset(y: CGFloat(SpringFlight.peekOffset(depth: depth, lift: lift, peek: Double(SpringSheetLayout.peek))))
                        .offset(x: depth == 0 ? drag : 0)
                        .rotationEffect(.degrees(depth == 0 && !reduceMotion ? SpringSwipe.rotation(translation: drag, width: Double(side)) : 0), anchor: .bottom)
                        .opacity(depth == 0 ? frontOpacity : (depth == 1 ? 0.85 : 0))
                        .zIndex(Double(3 - depth))
                        .allowsHitTesting(depth == 0)
                    }
                }
                .frame(width: side, height: SpringSheetLayout.deckHeight, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onAppear { cardWidth = Double(side) }
            }
        }
        .background {
            SpringDeckInput(
                focusToken: focusToken,
                onMove: { value in
                    guard !busy, model.bucket.deck.current != nil else { return }
                    drag = value
                },
                onRelease: { value in finish(SpringSwipe.choice(translation: value)) },
                onChoice: { finish($0) }
            )
            .focusEffectDisabled()
        }
        .onAppear { focusToken += 1 }
        .onChange(of: model.bucket.deck.current?.key) { focusToken += 1 }
    }

    private func face(_ card: UnopenedReference, playing: Bool, showsPlayer: Bool, side: CGFloat) -> some View {
        let plays = SpringMedia.plays(card)
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.card), style: .continuous)
        return SpringMediaCard(url: original(card), plays: plays, playing: playing, showsPlayer: showsPlayer, side: side, shape: shape)
    }

    private func original(_ card: UnopenedReference) -> URL? {
        let root = model.layout?.root ?? ProcessInfo.processInfo.environment["GRAILS_LIBRARY"].map { URL(fileURLWithPath: $0) }
        guard let root else { return nil }
        let id = SpringMedia.itemID(for: card.key)
        guard !id.isEmpty else { return nil }
        let url = LibraryLayout(root: root).itemDir(id).appendingPathComponent(SpringMedia.fileName(ext: card.ext))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !busy else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                finish(SpringSwipe.choice(translation: value.translation.width))
            }
    }

    private func finish(_ choice: SpringChoice) {
        if busy {
            if choice != .springBack { pending = choice }
            return
        }
        guard canAct else { return }
        switch choice {
        case .springBack:
            withAnimation(.grailsSpring(reduceMotion: reduceMotion)) { drag = 0 }
        case .keep, .chuck:
            busy = true
            let dest = SpringSwipe.rest(translation: choice == .keep ? SpringSwipe.threshold : -SpringSwipe.threshold, width: Double(cardSide))
            let settle = reduceMotion ? Motion.standard : SpringFlight.settle
            if reduceMotion {
                withAnimation(.grailsStandard) {
                    drag = 0
                    lift = 1
                    frontOpacity = 0
                }
            } else {
                withAnimation(.grailsSpring) {
                    drag = dest
                    lift = 1
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(Int(settle * 1000)))
                await apply(choice)
            }
        }
    }

    private func apply(_ choice: SpringChoice) async {
        let key = model.bucket.deck.current?.key
        if choice == .keep {
            model.bucket.springKeep()
        } else if choice == .chuck {
            await model.bucket.springChuck()
        }
        let failed = model.bucket.deck.current?.key == key
        if failed {
            withAnimation(reduceMotion ? .grailsStandard : .grailsSpring) {
                drag = 0
                lift = 0
                frontOpacity = 1
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = 0
                lift = 0
                frontOpacity = 1
            }
        }
        busy = false
        focusToken += 1
        if let next = pending {
            pending = nil
            finish(next)
        }
    }
}

/// One square. The picture or video fills it and is cropped from the centre.
private struct SpringMediaCard: View {
    var url: URL?
    var plays: Bool
    var playing: Bool
    var showsPlayer: Bool
    var side: CGFloat
    var shape: RoundedRectangle
    @State private var image: NSImage?

    var body: some View {
        GrailsSquareMedia(side: side) {
            ZStack {
                if plays, let url {
                    if let image { filled(image) }
                    if showsPlayer {
                        SpringVideoCard(url: url, playing: playing)
                    }
                } else if let image {
                    filled(image)
                }
            }
        }
        .background(Ink.fill, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Ink.hairline, lineWidth: 1) }
        .task(id: url) { await load() }
    }

    private func filled(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .clipped()
    }

    /// Centre-crop to a square bitmap so a portrait original cannot stretch the card or its accessibility frame.
    static func croppedSquare(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = source.width
        let height = source.height
        let edge = min(width, height)
        guard edge > 0 else { return image }
        let origin = CGPoint(x: (width - edge) / 2, y: (height - edge) / 2)
        guard let cropped = source.cropping(to: CGRect(origin: origin, size: CGSize(width: edge, height: edge))) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: edge, height: edge))
    }

    private func load() async {
        guard let url else { return }
        if plays {
            let poster = await SpringFrame.poster(url)
            guard !Task.isCancelled else { return }
            if let poster { image = Self.croppedSquare(poster) }
        } else {
            let data = await SpringFrame.bytes(url)
            guard !Task.isCancelled, let data, let loaded = NSImage(data: data) else { return }
            image = Self.croppedSquare(loaded)
        }
    }
}

private enum SpringFrame {
    /// File bytes, off the main thread. A large original must not stall the sheet's first paint.
    static func bytes(_ url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: try? Data(contentsOf: url))
            }
        }
    }

    static func poster(_ url: URL) async -> NSImage? {
        let rendered: CGImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 960, height: 960)
                let time = CMTime(seconds: 0.4, preferredTimescale: 600)
                continuation.resume(returning: try? generator.copyCGImage(at: time, actualTime: nil))
            }
        }
        guard let rendered else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }
}

private struct SpringVideoCard: NSViewRepresentable {
    var url: URL
    var playing: Bool

    func makeNSView(context: Context) -> SpringPlayerView {
        let view = SpringPlayerView()
        view.setAccessibilityElement(false)
        view.setPlaying(url, playing: playing)
        return view
    }

    func updateNSView(_ view: SpringPlayerView, context: Context) {
        view.setPlaying(url, playing: playing)
    }

    static func dismantleNSView(_ view: SpringPlayerView, coordinator: ()) {
        view.pause()
    }
}

private final class SpringPlayerView: NSView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var loop: NSObjectProtocol?
    private var current: URL?
    private var wantsPlay = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = nil
        playerLayer.masksToBounds = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if playerLayer.superlayer == nil, let layer {
            layer.masksToBounds = true
            layer.addSublayer(playerLayer)
        }
        playerLayer.frame = bounds
    }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPlaying(_ url: URL, playing: Bool) {
        wantsPlay = playing
        if current != url {
            current = url
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            loop.map { NotificationCenter.default.removeObserver($0) }
            loop = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.wantsPlay else { return }
                    self.player.seek(to: .zero)
                    self.player.play()
                }
            }
        }
        player.isMuted = true
        if playing {
            if player.rate == 0 { player.play() }
        } else {
            player.pause()
        }
    }

    func pause() {
        wantsPlay = false
        player.pause()
        if let loop {
            NotificationCenter.default.removeObserver(loop)
            self.loop = nil
        }
    }
}

/// Trackpad swipes and arrow keys. The view itself does not take clicks; the card's drag gesture does.
private struct SpringDeckInput: NSViewRepresentable {
    var focusToken: Int
    var onMove: (Double) -> Void
    var onRelease: (Double) -> Void
    var onChoice: (SpringChoice) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = SpringPassView()
        view.focusRingType = .none
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onRelease = onRelease
        context.coordinator.onChoice = onChoice
        let view = nsView as? SpringPassView
        view?.onChoice = onChoice
        view?.focusRingType = .none
        _ = focusToken
        view?.claimFocus()
        context.coordinator.generation = SpringKeyHub.shared.arm(window: nsView.window, onChoice: onChoice)
        DispatchQueue.main.async {
            view?.claimFocus()
            SpringKeyHub.shared.note(window: view?.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
        SpringKeyHub.shared.disarm(generation: coordinator.generation)
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onMove: (Double) -> Void = { _ in }
        var onRelease: (Double) -> Void = { _ in }
        var onChoice: (SpringChoice) -> Void = { _ in }
        var accumulated = 0.0
        var monitor: Any?
        var generation = 0

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .scrollWheel, .keyDown]) { [weak self] event in
                let type = event.type
                let key = event.keyCode
                let delta = Double(event.deltaX)
                let scrollX = Double(event.scrollingDeltaX)
                let scrollY = Double(event.scrollingDeltaY)
                let phase = event.phase
                let window = event.window?.windowNumber ?? -1
                let location = event.locationInWindow
                let consume = MainActor.assumeIsolated {
                    self?.take(type: type, key: key, delta: delta, scrollX: scrollX, scrollY: scrollY, phase: phase, window: window, location: location) ?? false
                }
                return consume ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func take(type: NSEvent.EventType, key: UInt16, delta: Double, scrollX: Double, scrollY: Double, phase: NSEvent.Phase, window: Int, location: NSPoint) -> Bool {
            switch type {
            case .keyDown:
                return false
            case .swipe:
                guard view?.window?.windowNumber == window, overDeck(location) else { return false }
                if delta > 0 { onChoice(.keep) }
                else if delta < 0 { onChoice(.chuck) }
                return false
            case .scrollWheel:
                guard view?.window?.windowNumber == window, overDeck(location) else { return false }
                return scroll(x: scrollX, y: scrollY, phase: phase)
            default:
                return false
            }
        }

        func overDeck(_ location: NSPoint) -> Bool {
            guard let view else { return false }
            return view.bounds.contains(view.convert(location, from: nil))
        }

        func scroll(x: Double, y: Double, phase: NSEvent.Phase) -> Bool {
            let horizontal = abs(x) >= abs(y)
            guard horizontal || accumulated != 0 else { return false }
            if phase == .began { accumulated = 0 }
            if phase == .began || phase == .changed {
                accumulated += x
                onMove(accumulated)
            }
            if phase == .ended || phase == .cancelled {
                let value = accumulated
                accumulated = 0
                onRelease(value)
            }
            return false
        }
    }
}

/// Arrow keys outlive the deck's view coordinator. A local monitor owned by that coordinator was gone before the key arrived.
@MainActor
final class SpringKeyHub {
    static let shared = SpringKeyHub()
    private var onChoice: ((SpringChoice) -> Void)?
    private var windowNumber: Int?
    private var monitor: Any?
    private var lastCode: UInt16 = .max
    private var lastAt: TimeInterval = 0
    private var generation = 0

    @discardableResult
    func arm(window: NSWindow?, onChoice: @escaping (SpringChoice) -> Void) -> Int {
        generation += 1
        self.onChoice = onChoice
        if let window { windowNumber = window.windowNumber }
        guard monitor == nil else { return generation }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let eventWindow = event.window?.windowNumber ?? -1
            let handled = MainActor.assumeIsolated {
                SpringKeyHub.shared.handle(code: code, eventWindow: eventWindow)
            }
            return handled ? nil : event
        }
        return generation
    }

    func note(window: NSWindow?) {
        if let window { windowNumber = window.windowNumber }
    }

    func disarm(generation: Int) {
        guard generation == self.generation else { return }
        onChoice = nil
        windowNumber = nil
    }

    private func handle(code: UInt16, eventWindow: Int) -> Bool {
        guard let choice = SpringKeys.choice(keyCode: code), let onChoice else { return false }
        guard owns(eventWindow) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if code == lastCode, now - lastAt < 0.12 { return true }
        lastCode = code
        lastAt = now
        onChoice(choice)
        return true
    }

    private func owns(_ eventWindow: Int) -> Bool {
        guard let windowNumber else { return false }
        if windowNumber == eventWindow { return true }
        let host = NSApp.windows.first { $0.windowNumber == windowNumber }
        if eventWindow <= 0 { return host?.isKeyWindow == true || NSApp.keyWindow === host }
        return host?.isKeyWindow == true && NSApp.keyWindow === host
    }
}

private final class SpringPassView: GrailsKeyView {
    var onChoice: (SpringChoice) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func keyDown(with event: NSEvent) {
        guard let choice = SpringKeys.choice(keyCode: event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        onChoice(choice)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
        SpringKeyHub.shared.note(window: window)
    }
}

enum SpringProofMedia {
    static func writeImage(to url: URL) throws {
        let width = 800
        let height = 1040
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let base = rep.bitmapData else { return }
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let dx = x - 400
                let dy = y - 520
                let circle = dx * dx + dy * dy < 210 * 210
                if circle {
                    base[offset] = 239
                    base[offset + 1] = 239
                    base[offset + 2] = 236
                    base[offset + 3] = 255
                } else {
                    base[offset] = 26
                    base[offset + 1] = 26
                    base[offset + 2] = 26
                    base[offset + 3] = 255
                }
            }
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url, options: .atomic)
    }

    /// The whole encode runs off the main thread. Releasing a writer that is still open, on the main thread, never returns.
    static func writeVideo() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: encodeProofVideo())
            }
        }
    }

    nonisolated private static func encodeProofVideo() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grails-spring-proof.mp4")
        try? FileManager.default.removeItem(at: url)
        let width = 480
        let height = 270
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else {
            writer.cancelWriting()
            return nil
        }
        writer.add(input)
        guard writer.startWriting() else {
            writer.cancelWriting()
            return nil
        }
        writer.startSession(atSourceTime: .zero)
        let started = Date()
        for frame in 0..<16 {
            guard appendProofFrame(frame, width: width, height: height, input: input, adaptor: adaptor, started: started) else {
                writer.cancelWriting()
                return nil
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        if done.wait(timeout: .now() + 8) == .timedOut {
            writer.cancelWriting()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        return writer.status == .completed ? url : nil
    }

    nonisolated private static func appendProofFrame(_ frame: Int, width: Int, height: Int, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, started: Date) -> Bool {
        let wait = Date()
        while !input.isReadyForMoreMediaData {
            if Date().timeIntervalSince(wait) > 2 || Date().timeIntervalSince(started) > 8 { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { return false }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let pixels = base.bindMemory(to: UInt8.self, capacity: row * height)
            let bar = 40 + frame * 22
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * row + x * 4
                    let stripe = x >= bar && x < bar + 70
                    pixels[offset] = stripe ? 236 : 58
                    pixels[offset + 1] = stripe ? 239 : 92
                    pixels[offset + 2] = stripe ? 239 : 176
                    pixels[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 8))
    }
}
