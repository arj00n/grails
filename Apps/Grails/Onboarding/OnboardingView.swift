import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// First run, in the chromeless window: the paintings, a choice (import boards or start empty), the links to bring, and the pictures arriving.
struct OnboardingView: View {
    var model: OnboardingModel

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            switch model.step {
            case .hello, .choose: HelloChooseStep(model: model)
            case .whereIt: LibraryStep(model: model).transition(.opacity)
            case .paste, .arriving: ImportStep(model: model).transition(.opacity)
            }
            if model.teamSetup, let app = model.app {
                Ink.canvas.ignoresSafeArea().transition(.opacity)
                CollabSetupView(model: app) { model.closeTeamSetup() }
                    .frame(width: CollabSetupView.size.width, height: CollabSetupView.size.height)
                    .surfaceCard().transition(.opacity)
            }
            topBar
            Button("") { model.back() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .accessibilityIdentifier("onboarding")
    }

    private var topBar: some View {
        VStack {
            HStack {
                if model.step == .whereIt && !model.returning {
                    BarButton(symbol: "chevron.left", help: "Back (Esc)", identifier: "onboarding-back") { model.back() }.padding(.leading, 86)
                }
                Spacer()
            }
            .frame(height: 44)
            Spacer()
        }
    }
}

let reduceMotionOn: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

// MARK: Hello and Choose

/// The title plate over the painting wall; when `choosing`, the painting, Start and the caption fade away and the options fade in around the same
/// title, which doesn't move. Pure in `t`, so a headless snapshot can ask for any moment.
struct HelloFrame<Wall: View, Chooser: View>: View {
    let t: Double
    let size: CGSize
    var caption: String
    var choosing = false
    @ViewBuilder var wall: Wall
    @ViewBuilder var chooser: Chooser
    var start: () -> Void = {}

    private var curve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : 0.24) }

    var body: some View {
        let plate = PaintingWall.plate(window: size)
        ZStack(alignment: .topLeading) {
            wall.frame(width: size.width, height: size.height).opacity(choosing ? 0 : 1).animation(curve, value: choosing)
            VStack(spacing: 14) {
                title
                Button("Start", action: start)
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .opacity(choosing ? 0 : min(max((t - 1.3) / 0.1, 0), 1)).allowsHitTesting(t >= 1.3 && !choosing)
                    .animation(.easeOut(duration: 0.1), value: choosing)
                    .accessibilityIdentifier("onboarding-start")
            }
            .frame(width: plate.width, height: plate.height)
            .background(Ink.canvas)
            .offset(x: plate.minX, y: plate.minY)
            // the painter, bottom right, on a small plate of canvas so it reads over the painting; the centre stays clean. It cross-fades to the next one.
            ZStack(alignment: .bottomTrailing) {
                Text(caption).font(.grailsDisplay(12)).foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Ink.canvas)
                    .padding(16)
                    .id(caption).transition(.opacity)
            }
            .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
            .animation(.easeInOut(duration: reduceMotionOn ? 0.12 : 0.7), value: caption)
            .opacity(choosing ? 0 : min(max((t - 1.3) / 0.1, 0), 1))
            .animation(.easeOut(duration: 0.1), value: choosing)
            .allowsHitTesting(false)
            .accessibilityIdentifier("onboarding-caption")
            // laid out by offset, never padding: padding would make this child taller than the window and stretch the wall with it
            chooser
                .frame(width: size.width, alignment: .top)
                .offset(y: plate.minY + 84)
                .opacity(choosing ? 1 : 0).allowsHitTesting(choosing)
                .animation(choosing ? curve.delay(reduceMotionOn ? 0 : 0.1) : .easeOut(duration: 0.05), value: choosing)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Typed on at 40 ms a letter, starting after a second; once chosen it is simply there.
    private var title: some View {
        let word = Array("GRAILS")
        let typed = choosing ? word.count : min(max(Int((t - 1.0) / 0.04) + 1, 0), word.count)
        return ZStack(alignment: .leading) {
            Text("GRAILS").font(.grailsDisplay(32)).hidden()
            Text(String(word.prefix(typed))).font(.grailsDisplay(32)).foregroundStyle(Ink.text)
        }
        .accessibilityLabel("Grails")
    }
}

extension HelloFrame where Chooser == EmptyView {
    init(t: Double, size: CGSize, caption: String, @ViewBuilder wall: () -> Wall, start: @escaping () -> Void = {}) {
        self.init(t: t, size: size, caption: caption, choosing: false, wall: wall, chooser: { EmptyView() }, start: start)
    }
}

/// The two (or three) cards: bring boards in, start empty, or join a library already found in a synced folder.
struct ChooserCards: View {
    var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                if let f = model.found.first {
                    card("Join \(f.name)", fact: "In your synced folder", id: "choose-join") { model.join(f) }
                }
                card("Import boards", fact: "Are.na · Pinterest · X", id: "choose-import", primary: true) { model.importBoards() }
                card("Start empty", fact: nil, id: "choose-empty") { model.startEmpty() }
            }
            .frame(width: model.found.isEmpty ? 544 : 560)
            HStack(spacing: 16) {
                Button(model.chosenPath.isEmpty ? "Choose where it lives" : model.chosenPath) { model.go(.whereIt) }
                    .accessibilityIdentifier("choose-location")
                Button("Set up a team library") { model.openTeamSetup() }
                    .accessibilityIdentifier("choose-team")
            }
            .buttonStyle(.plain).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            Button("") { model.pasteFromClipboard() }.keyboardShortcut("v", modifiers: .command).frame(width: 0, height: 0).opacity(0)
        }
    }

    private func card(_ title: String, fact: String?, id: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        ChooserCard(title: title, fact: fact, primary: primary, action: action).accessibilityIdentifier(id)
    }
}

private struct ChooserCard: View {
    let title: String
    let fact: String?
    var primary = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text).lineLimit(1)
                if let fact { Text(fact).font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).fill(hovering ? Ink.fill : Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(primary ? Ink.text.opacity(0.5) : Ink.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .keyboardShortcut(primary ? .defaultAction : nil)
    }
}

private struct HelloChooseStep: View {
    var model: OnboardingModel
    @State private var epoch = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotionOn || model.step == .choose)) { timeline in
                let t = reduceMotionOn ? 10 : timeline.date.timeIntervalSince(epoch)
                let specs = PaintingWallEngine.shared?.specs ?? []
                let shown = PaintingWall.captionIndex(PaintingWall.schedule(t: t, count: specs.count, reduceMotion: reduceMotionOn))
                HelloFrame(t: t, size: geo.size, caption: specs.indices.contains(shown) ? specs[shown].caption : "", choosing: model.step == .choose,
                           wall: { PaintingWallBackground(epoch: epoch, reduceMotion: reduceMotionOn) }, chooser: { ChooserCards(model: model) }) { model.start() }
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
                Button("Continue") { model.returning ? model.continueFromLibrary(next: .finish) : model.confirmLocation() }
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

// MARK: Paste and Arriving

/// One screen for both. Before the import runs the column is centred, like every step before it; when it runs the same column moves to the
/// right edge and takes its counter while the pictures fill in on the left. Nothing is rebuilt: the column's frame, alignment and header animate.
struct ImportScreen: View {
    var model: OnboardingModel
    var app: AppModel
    var grid: ArrivalGridModel
    var arriving: Bool
    var elapsed: Double
    var eta: Eta

    @State private var natural: CGFloat = 0
    private var curve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : 0.24) }

    var body: some View {
        GeometryReader { geo in
            // before the import runs the column is as tall as what is in it, centred, and grows with the boards; once it runs it is the full height
            let room = max(geo.size.height - 120, 200)
            let pasteHeight = natural > 0 ? min(natural, room) : min(240, room)
            ZStack(alignment: .topLeading) {
                ArrivalGrid(model: grid, app: app)
                    .padding(.leading, 16).padding(.top, 52).padding(.trailing, ProgressColumn.width + 16)
                    .opacity(arriving ? 1 : 0).allowsHitTesting(arriving)
                ProgressColumn(model: model, app: app, arriving: arriving, elapsed: elapsed, eta: eta, listCap: max(room - 240, 120)) { natural = $0 }
                    .frame(width: arriving ? ProgressColumn.width : 560, height: arriving ? geo.size.height - 44 : pasteHeight, alignment: .top)
                    .offset(x: arriving ? geo.size.width - ProgressColumn.width : (geo.size.width - 560) / 2,
                            y: arriving ? 44 : max((geo.size.height - pasteHeight) / 2, 44))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(curve, value: arriving)
        .animation(.easeOut(duration: 0.2), value: natural)
        .ignoresSafeArea()
    }
}

private struct ColumnHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The boards column: Import boards (the field, the rows, Import) that becomes Importing (the counter, the rows, Stop and Open library).
struct ProgressColumn: View {
    var model: OnboardingModel
    var app: AppModel
    var arriving = true
    var elapsed: Double
    var eta: Eta
    /// The tallest the rows grow before they scroll, while the column is still hugging them.
    var listCap: CGFloat = 300
    /// The height the content wants before the import runs.
    var onNaturalHeight: ((CGFloat) -> Void)?

    static let width: CGFloat = 340

    var body: some View {
        let importer = app.importModel
        let total = max(importer.tasks.values.reduce(0) { $0 + $1.expected }, 1)
        let done = importer.tasks.values.reduce(0) { $0 + $1.handled.count }
        let paused = importer.tasks.values.contains { if case .waiting = $0.state { true } else { false } }
        let picked = importer.selectedItemCount
        VStack(alignment: .leading, spacing: 14) {
            if arriving {
                VStack(alignment: .leading, spacing: 14) {
                    Text("IMPORTING").font(.grailsDisplay(12)).foregroundStyle(Ink.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(done.formatted()) / \(total.formatted())").font(.grailsDisplay(24)).monospacedDigit().foregroundStyle(Ink.text)
                            .accessibilityLabel("\(done) of \(total) pictures")
                            .accessibilityIdentifier("onboarding-counter")
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Ink.fill)
                            GeometryReader { g in Rectangle().fill(Ink.text).frame(width: g.size.width * min(CGFloat(done) / CGFloat(total), 1)) }
                        }
                        .frame(height: 2)
                        HStack {
                            Text(paused ? "Paused" : (eta.label(handled: done, total: total, elapsed: elapsed, paused: paused) ?? " "))
                                .font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                            Spacer()
                            Text("\(Int(min(Double(done) / Double(total), 1) * 100)) %").font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Text("IMPORT BOARDS").font(.grailsDisplay(16)).foregroundStyle(Ink.text).transition(.opacity)
            }
            ImportView(model: importer, app: app, hug: !arriving, listHeight: arriving ? nil : listCap)
            ZStack(alignment: .trailing) {
                HStack {
                    Button("Stop") { importer.stopAll() }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary).opacity(importer.isRunning ? 1 : 0)
                    Spacer()
                    Button("Open library") { model.finish() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(arriving ? .defaultAction : nil).accessibilityIdentifier("onboarding-open")
                }
                .opacity(arriving ? 1 : 0).allowsHitTesting(arriving)
                Button(picked > 0 ? "Import \(picked.formatted()) pictures" : "Import") { model.startImport() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(importer.selectedBoards.isEmpty)
                    .keyboardShortcut(arriving ? nil : .defaultAction).accessibilityIdentifier("onboarding-import")
                    .opacity(arriving ? 0 : 1).allowsHitTesting(!arriving)
            }
        }
        .padding(arriving ? 16 : 0)
        .fixedSize(horizontal: false, vertical: !arriving)
        .background(GeometryReader { g in Color.clear.preference(key: ColumnHeightKey.self, value: g.size.height) })
        .onPreferenceChange(ColumnHeightKey.self) { h in if !arriving, h > 0 { onNaturalHeight?(h) } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.surface.opacity(arriving ? 1 : 0))
        .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1).opacity(arriving ? 1 : 0) }
    }
}

/// The whole Arriving screen, for the headless snapshots.
struct ArrivingScreen: View {
    var model: OnboardingModel
    var app: AppModel
    var grid: ArrivalGridModel
    var elapsed: Double
    var eta: Eta

    var body: some View { ImportScreen(model: model, app: app, grid: grid, arriving: true, elapsed: elapsed, eta: eta) }
}

/// Paste and Arriving as one screen that stays mounted from the field to the finished grid.
struct ImportStep: View {
    var model: OnboardingModel
    @State private var grid = ArrivalGridModel(reduceMotion: reduceMotionOn)
    @State private var started = Date()
    @State private var eta = Eta()
    @State private var elapsed = 0.0

    var body: some View {
        if let app = model.app {
            ImportScreen(model: model, app: app, grid: grid, arriving: model.step == .arriving, elapsed: elapsed, eta: eta)
                // the import may need a moment to start: the screen follows once it actually runs
                .onChange(of: app.importModel.phase) { _, phase in
                    if phase == .running { model.go(.arriving) }
                    // everything has arrived and the library is laid out underneath: a short hold, then the crossfade into it
                    if phase == .finished, model.step == .arriving { model.landWhenReady() }
                }
                .onChange(of: model.step) { _, step in if step == .arriving { begin(app) } }
                .onAppear { if model.step == .arriving { begin(app) } }
                .onDisappear { grid.stop() }
                .task(id: model.step == .arriving) {
                    // the pace of the last half minute, once a second
                    guard model.step == .arriving else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        elapsed = Date().timeIntervalSince(started)
                        eta.add(handled: app.importModel.tasks.values.reduce(0) { $0 + $1.handled.count }, at: elapsed)
                    }
                }
        }
    }

    private func begin(_ app: AppModel) {
        grid.run(app: app)
        started = Date()
    }
}
