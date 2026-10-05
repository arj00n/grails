import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// First run, in the chromeless window: a wall waiting for pictures, where the library lives, the boards to bring, and the wall filling.
struct OnboardingView: View {
    var model: OnboardingModel

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            switch model.step {
            case .hello: HelloStep(model: model).transition(.opacity)
            case .library: LibraryStep(model: model).transition(.opacity)
            case .importing: ImportStep(model: model).transition(.opacity)
            case .arriving: ArrivingStep(model: model).transition(.opacity)
            }
            topBar
            Button("") { model.back() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .accessibilityIdentifier("onboarding")
    }

    private var topBar: some View {
        VStack {
            HStack {
                if model.step == .library && !model.returning {
                    BarButton(symbol: "chevron.left", help: "Back (Esc)", identifier: "onboarding-back") { model.back() }.padding(.leading, 86)
                }
                Spacer()
                if model.step != .arriving {
                    Button("Skip") { model.skip() }
                        .buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                        .padding(.trailing, 20).accessibilityIdentifier("onboarding-skip")
                }
            }
            .frame(height: 44)
            Spacer()
        }
    }
}

let reduceMotionOn: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

// MARK: Hello

/// The title plate over the wall: a hard-edged canvas rectangle holding the name, Start and the painting's caption. Pure in `t`, so a
/// headless snapshot can ask for any moment; `wall` is the live painting (or, in a snapshot, a picture of it).
struct HelloFrame<Wall: View>: View {
    let t: Double
    let size: CGSize
    var caption: String
    @ViewBuilder var wall: Wall
    var start: () -> Void = {}

    var body: some View {
        let plate = PaintingWall.plate(window: size)
        ZStack(alignment: .topLeading) {
            wall
            VStack(spacing: 14) {
                title
                Button("Start", action: start)
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .opacity(min(max((t - 1.3) / 0.1, 0), 1)).allowsHitTesting(t >= 1.3)
                    .accessibilityIdentifier("onboarding-start")
                Text(caption).font(.grailsDisplay(12)).foregroundStyle(Ink.secondary)
                    .opacity(min(max((t - 1.3) / 0.1, 0), 1))
                    .id(caption).transition(.opacity)
                    .animation(.easeOut(duration: Motion.standard / 2), value: caption)
                    .accessibilityIdentifier("onboarding-caption")
            }
            .frame(width: plate.width, height: plate.height)
            .background(Ink.canvas)
            .offset(x: plate.minX, y: plate.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Typed on at 40 ms a letter, starting after a second.
    private var title: some View {
        let word = Array("GRAILS")
        let typed = min(max(Int((t - 1.0) / 0.04) + 1, 0), word.count)
        return ZStack(alignment: .leading) {
            Text("GRAILS").font(.grailsDisplay(32)).hidden()
            Text(String(word.prefix(typed))).font(.grailsDisplay(32)).foregroundStyle(Ink.text)
        }
        .accessibilityLabel("Grails")
    }
}

private struct HelloStep: View {
    var model: OnboardingModel
    @State private var epoch = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotionOn)) { timeline in
                let t = reduceMotionOn ? 10 : timeline.date.timeIntervalSince(epoch)
                let specs = PaintingWallEngine.shared?.specs ?? []
                let shown = PaintingWall.captionIndex(PaintingWall.schedule(t: t, count: specs.count, reduceMotion: reduceMotionOn))
                HelloFrame(t: t, size: geo.size, caption: specs.indices.contains(shown) ? specs[shown].caption : "",
                           wall: { PaintingWallBackground(epoch: epoch, reduceMotion: reduceMotionOn) }) { model.start() }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Library

struct LibraryStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("WHERE IT LIVES").font(.grailsDisplay(16)).foregroundStyle(Ink.text)
            VStack(alignment: .leading, spacing: 2) {
                row(.thisMac, "This Mac", model.thisMac.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), id: "library-this-mac")
                ForEach(model.roots) { r in row(.root(r.id), r.name, nil, id: "library-root") }
                ForEach(model.found) { f in row(.found(f.id), f.name, "Found", id: "library-found") }
                row(.other, "Other folder", model.otherURL.map(OnboardingModel.tilde), id: "library-other") { model.chooseFolder() }
                row(.link, "Join with link", nil, id: "library-link") { linkFocused = true }
                if model.choice == .link {
                    TextField("grails://open?lib=", text: $model.linkText)
                        .textFieldStyle(.plain).font(.grailsBody(13)).focused($linkFocused)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
                        .padding(.leading, 30).padding(.top, 2)
                        .onAppear { linkFocused = true }
                        .accessibilityIdentifier("library-link-field")
                }
            }
            HStack(spacing: 12) {
                Text("Name").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                TextField("", text: $model.handle)
                    .textFieldStyle(.plain).font(.grailsBody(13))
                    .padding(.horizontal, 10).frame(width: 200, height: 30)
                    .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
                    .onSubmit { model.continueFromLibrary() }
                    .accessibilityIdentifier("library-name")
            }
            HStack {
                if let p = model.problem { Text(p).font(.grailsBody(12)).foregroundStyle(Ink.destructive) }
                Spacer()
                Button("Continue") { model.continueFromLibrary() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!model.canContinue)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("library-continue")
            }
        }
        .frame(width: 460)
        .onAppear { model.scan() }
    }

    private func row(_ choice: OnboardingModel.Choice, _ title: String, _ detail: String?, id: String, extra: (() -> Void)? = nil) -> some View {
        LibraryRow(selected: model.choice == choice, title: title, detail: detail) {
            model.choice = choice
            extra?()
        }
        .accessibilityIdentifier(id)
    }
}

private struct LibraryRow: View {
    let selected: Bool
    let title: String
    let detail: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Ink.text : Ink.tertiary, lineWidth: 1).frame(width: 14, height: 14)
                    if selected { Circle().fill(Ink.text).frame(width: 6, height: 6) }
                }
                Text(title).font(.grailsBody(13)).foregroundStyle(Ink.text).lineLimit(1)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.middle) }
            }
            .padding(.horizontal, 8).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fill : (hovering ? Ink.fill.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Import

struct ImportStep: View {
    var model: OnboardingModel

    var body: some View {
        if let app = model.app {
            let importer = app.importModel
            VStack(alignment: .leading, spacing: 18) {
                Text("BRING YOUR BOARDS").font(.grailsDisplay(16)).foregroundStyle(Ink.text)
                ImportView(model: importer, app: app, listHeight: 340)
                HStack {
                    Spacer()
                    Button(importer.selectedItemCount > 0 ? "Import \(importer.selectedItemCount.formatted()) items" : "Import") { model.startImport() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(importer.selectedBoards.isEmpty)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("onboarding-import")
                }
            }
            .frame(width: 560)
        }
    }
}

// MARK: Arriving

/// The wall beside the rows: pictures take their tiles as they land, the counter reads like a tape.
struct ArrivingFrame: View {
    let slots: [Mosaic.Slot]
    let size: CGSize
    let t: Double
    var wall: WallModel
    var done: Int
    var total: Int

    static let cardWidth: CGFloat = 300
    /// The wall is laid out in the room left of the card: the same seed as Hello, fewer columns.
    static func wall(_ size: CGSize) -> CGSize { CGSize(width: max(size.width - cardWidth - 48, 0), height: size.height) }
    static func card(_ size: CGSize) -> CGRect { CGRect(x: size.width - cardWidth - 24, y: 56, width: cardWidth, height: size.height - 56 - 24) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MosaicCanvas(slots: slots, t: t, pictures: wall.pictures)
            Text(String(format: "%04d / %04d", done, max(total, done)))
                .font(.grailsDisplay(16)).monospacedDigit().foregroundStyle(Ink.text)
                .padding(.horizontal, 8).frame(height: 28)
                .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
                .padding(.leading, 86).padding(.top, 8)
                .accessibilityIdentifier("onboarding-counter")
        }
    }
}

/// The whole Arriving screen at one moment: the wall, and the rows in a card beside it.
struct ArrivingScreen: View {
    var model: OnboardingModel
    var app: AppModel
    var wall: WallModel
    let slots: [Mosaic.Slot]
    let size: CGSize
    let t: Double

    var body: some View {
        let importer = app.importModel
        let total = max(importer.tasks.values.reduce(0) { $0 + $1.expected }, 1)
        let done = importer.tasks.values.reduce(0) { $0 + $1.handled.count }
        let card = ArrivingFrame.card(size)
        ZStack(alignment: .topLeading) {
            ArrivingFrame(slots: slots, size: size, t: t, wall: wall, done: done, total: total)
            VStack(alignment: .leading, spacing: 12) {
                ImportView(model: importer, app: app, listHeight: nil)
                Spacer(minLength: 0)
                HStack {
                    Button("Stop All") { importer.stopAll() }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                        .opacity(importer.isRunning ? 1 : 0)
                    Spacer()
                    Button("Open library") { model.finish() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding-open")
                }
            }
            .padding(14)
            .frame(width: card.width, height: card.height, alignment: .topLeading)
            .surfaceCard()
            .offset(x: card.minX, y: card.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

struct ArrivingStep: View {
    var model: OnboardingModel
    @State private var wall = WallModel()

    var body: some View {
        if let app = model.app {
            GeometryReader { geo in
                let slots = Mosaic.layout(seed: model.seed, size: ArrivingFrame.wall(geo.size))
                WallClock(reduceMotion: reduceMotionOn, wall: wall) { t in
                    ArrivingScreen(model: model, app: app, wall: wall, slots: slots, size: geo.size, t: t)
                }
                .onAppear { wall.configure(slots: slots, reserved: nil); wall.run(app: app, reduceMotion: reduceMotionOn) }
                .onChange(of: geo.size) { wall.configure(slots: Mosaic.layout(seed: model.seed, size: ArrivingFrame.wall(geo.size)), reserved: nil) }
                .onDisappear { wall.stop() }
            }
            .ignoresSafeArea()
            .onChange(of: app.importModel.phase) { _, phase in
                // everything has arrived: a short hold on the full wall, then into the library
                if phase == .finished { Task { try? await Task.sleep(for: .milliseconds(600)); model.finish() } }
            }
        }
    }
}
