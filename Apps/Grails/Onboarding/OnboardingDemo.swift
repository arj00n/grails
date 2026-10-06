import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Dev only (GRAILS_ONBOARDING_DEMO=<dir>): walks the whole first run with a stand-in network and a fake home folder (one synced
/// drive holding a library), paints each screen to a PNG in light and dark, and writes `result.txt`. No screen, no network, and the
/// person's own preferences and library are left alone.
extension AppModel {
    func startOnboardingDemo(_ dir: String) async {
        needsLibrary = true
        let suite = UserDefaults(suiteName: "xyz.arjoon.grails.onboarding-demo")!
        suite.removePersistentDomain(forName: "xyz.arjoon.grails.onboarding-demo")
        let o = OnboardingModel(app: self, defaults: suite)
        let root = URL(fileURLWithPath: dir)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        o.thisMac = root.appendingPathComponent("This Mac.grails")
        o.home = root.appendingPathComponent("home")
        o.remember = false
        let drive = o.home.appendingPathComponent("Library/CloudStorage/GoogleDrive-ana@studio.com/Shared drives/Design")
        try? FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        _ = try? LibraryStore.create(at: drive.appendingPathComponent("Team Inspo.grails"), name: "Team Inspo", index: nil, userHandle: "ana")
        importModel.loader = ImportFixture.loader
        importModel.fixtureNetwork = true
        onboarding = o
        await startCapture()
        Task { @MainActor in await OnboardingDemo(app: self, model: o, dir: dir).run() }
    }
}

@MainActor
struct OnboardingDemo {
    let app: AppModel
    let model: OnboardingModel
    let dir: String
    let size = CGSize(width: 1280, height: 800)

    func run() async {
        var log: [String] = []
        var failed = false
        func say(_ s: String) { log.append(s); try? log.joined(separator: "\n").write(toFile: dir + "/result.txt", atomically: true, encoding: .utf8) }
        func check(_ ok: Bool, _ what: String) { say((ok ? "ok   " : "FAIL ") + what); if !ok { failed = true } }
        func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func until(_ seconds: Double, _ cond: () -> Bool) async { for _ in 0..<Int(seconds * 10) where !cond() { await wait(100) } }

        app.extensionPaired = false
        // Hello: the paintings, the cross-construct between them, the shimmer, the plate with its caption
        let engine = PaintingWallEngine.shared
        check(engine != nil && engine!.specs.count == 14, "painting manifest loads: \(engine?.specs.count ?? 0) works")
        if let engine {
            for i in engine.specs.indices { engine.prepare(i, size: size) }
            func hello(_ name: String, t: Double, reduceMotion: Bool = false, size: CGSize = size, indices: Bool = true) {
                let sched = PaintingWall.schedule(t: t, count: engine.specs.count, reduceMotion: reduceMotion)
                let caption = engine.specs[PaintingWall.captionIndex(sched)].caption
                snap({ dark in
                    HelloFrame(t: t, size: size, caption: caption, wall: {
                        if let img = engine.render(size: size, t: t, dark: dark, reduceMotion: reduceMotion) { Image(decorative: img, scale: 1).resizable() }
                    })
                }, name, size: size)
            }
            for (name, t) in [("0000", 0.05), ("0450", 0.45), ("0900", 0.9), ("1300", 1.3)] { hello("hello-\(name)", t: t) }
            for i in engine.specs.indices { hello("hello-rest-\(engine.specs[i].id)", t: PaintingWall.period * Double(i) + 7) }
            for (n, p) in [(10, 0.1), (25, 0.25), (50, 0.5), (75, 0.75), (90, 0.9)] { hello("hello-transition-\(n)", t: PaintingWall.period + PaintingWall.transition * p) }
            hello("hello-reduce-motion", t: 10, reduceMotion: true)
            say(shimmerReport(engine))
            say(bench(engine))
        }
        check(model.step == .hello, "starts on Hello")

        // Choose: the options fade in around the title; a library found in the synced drive is offered as Join
        model.start()
        check(model.step == .choose, "Start goes to Choose")
        await until(5) { !model.found.isEmpty }
        await wait(400)
        check(model.found.map(\.name) == ["Team Inspo"], "the library in the synced drive is found: \(model.found.map(\.name))")
        snap({ _ in HelloFrame(t: 10, size: size, caption: "", choosing: true, wall: { Color.clear }, chooser: { ChooserCards(model: model) }) }, "choose")
        snap(ZStack { LibraryStep(model: model) }, "where")

        // The ink band at the foot of Choose: settles by itself, stays finite when stirred, and draws as a dithered bitmap
        let fluid = FluidField()
        fluid.resize(320, 70)
        for _ in 0..<200 { fluid.step(1 / 60, stir: nil) }
        for i in 0..<90 { fluid.step(1 / 60, stir: .init(x: 40 + Float(i) * 2.5, y: 38 + 12 * sin(Float(i) / 9), vx: 2.2, vy: -1.4)) }
        if let img = fluid.image(ink: (255, 255, 255), paper: (0, 0, 0)) {
            let rep = NSBitmapImageRep(cgImage: img)
            check(img.width == 320 && img.height == 70, "the ink band renders at its grid size")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/snap-fluid-band.png"))
        } else { check(false, "the ink band renders") }
        let probe = fluid.image(ink: (255, 255, 255), paper: (0, 0, 0))
        check(probe != nil, "stirred ink stays a valid picture (no runaway values)")

        // Choose → Import boards: the library is made without asking, then Paste
        model.importBoards()
        await until(10) { model.step == .paste }
        check(model.step == .paste && app.store != nil, "Import boards makes the library and goes to Paste")
        check(FileManager.default.fileExists(atPath: dir + "/This Mac.grails/library.json"), "library made on This Mac with no questions")

        // Back from Paste: never a dead end. The empty library made on the way in is thrown away, and Choose works again
        model.back()
        await until(10) { model.step == .choose }
        check(model.step == .choose && app.store == nil && app.needsLibrary, "Back from Paste returns to Choose with no library left")
        check(!FileManager.default.fileExists(atPath: dir + "/This Mac.grails/library.json"), "the empty library it made is gone")
        model.importBoards()
        await until(10) { model.step == .paste }
        check(model.step == .paste && app.store != nil, "Import boards works again after going back")

        // Paste: a Pinterest board of 240 pins is read by the in-app reader (a real web view against a stand-in server), no extension
        let fixture = CollectorFixture(pins: 240)
        let port = (try? await fixture.start()) ?? 0
        PinterestCollector.shared.origin = URL(string: "http://127.0.0.1:\(port)")!
        app.importModel.ingest("""
        https://www.are.na/ana/demo-one and pinterest.com/ana/interiors/, plus https://www.are.na/demo
        also https://example.com/x
        """)
        await until(10) { !app.importModel.stillChecking }
        app.importModel.setSelected("arena:other-one", true)
        check(app.importModel.banner == .wholeBoard(latestOnly: false), "a board over 50 pins shows the banner and defaults to the whole board: \(String(describing: app.importModel.banner))")
        check(app.importModel.selectedBoards.contains { $0.via == .collector }, "the big board is routed to the in-app reader")
        let whole = app.importModel.selectedItemCount
        snap(ZStack { ImportStep(model: model) }, "paste")
        app.importModel.setLatestOnly(true)
        check(app.importModel.selectedItemCount < whole && app.importModel.banner == .wholeBoard(latestOnly: true), "Latest 50 only changes the total: \(whole) → \(app.importModel.selectedItemCount)")
        snap(ZStack { ImportStep(model: model) }, "paste-latest-only")
        app.importModel.setLatestOnly(false)
        check(app.importModel.selectedItemCount == whole, "Get all restores it")
        // the extension is no longer in the way: the sheet is reached only on request
        check(!app.extensionSetup.isOpen && model.step == .paste, "no extension sheet and no browser on the default path")

        // A secret board: flagged, then (extension connected) read in the browser like any other; and the floating guide that lists the steps
        app.importModel.ingest("https://www.pinterest.com/ana/secret-one/")
        await until(10) { !app.importModel.stillChecking }
        check(app.importModel.secretRows == 1 && app.importModel.banner == .secret, "a secret board is flagged and the banner points at the extension")
        snap(ZStack { ImportStep(model: model) }, "paste-secret")
        app.extensionPaired = true
        app.importModel.useExtensionForSecretBoards()
        check(app.importModel.secretRows == 0 && app.importModel.selectedBoards.contains { $0.via == .browser && $0.id == "pinterest:ana/secret-one" }, "once the extension is connected the secret board becomes an importable board")
        app.extensionPaired = false
        if let row = app.importModel.rows.first(where: { $0.id == "pinterest:ana/secret-one" }) { app.importModel.remove(row.id) }
        app.guide.set(title: "Adding the extension", steps: [("Turn on Developer mode, top right of the page", .done), ("Drag the folder below onto the page", .current), ("Grails connects by itself", .pending)],
                      folder: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Grails/Extension"))
        snap(ZStack { Color.clear; GuideView(model: app.guide, close: {}).frame(width: 320).position(x: 640, y: 300) }, "guide-extension")
        app.guide.set(title: "Reading your board", steps: [("Sign in to Pinterest in the tab that opened, if it asks", .done), ("Leave the tab open while Grails reads the board", .current), ("Grails comes back by itself when it's done", .pending)])
        app.guide.status = "Reading 640 pins"
        snap(ZStack { Color.clear; GuideView(model: app.guide, close: {}).frame(width: 320).position(x: 640, y: 300) }, "guide-reading")

        // Arriving: pictures join the grid a few at a time and never move once shown
        var opened: [String] = []
        app.browserOpener = { opened.append($0) }
        model.startImport()
        await until(10) { model.step == .arriving }
        check(model.step == .arriving, "Import goes on to Arriving (no sheet, no browser)")
        let grid = ArrivalGridModel(reduceMotion: false)
        grid.configure(width: size.width - ProgressColumn.width - 32, height: size.height - 52)
        grid.run(app: app)
        var eta = Eta()
        var earlier: [[ArrivalGridModel.Tile]]?
        var stable = true
        var snaps = 0
        let began = Date()
        while app.importModel.phase == .running, snaps < 4 {
            await wait(700)
            let now = Date().timeIntervalSince(began)
            eta.add(handled: app.importModel.tasks.values.reduce(0) { $0 + $1.handled.count }, at: now)
            let cols = grid.columns
            if let before = earlier { for c in before.indices where c < cols.count { if Array(cols[c].prefix(before[c].count)) != before[c] { stable = false } } }
            earlier = cols
            snap(ArrivingScreen(model: model, app: app, grid: grid, elapsed: now, eta: eta), "arriving-\(snaps)")
            snaps += 1
        }
        await until(40) { app.importModel.phase == .finished }
        check(app.importModel.phase == .finished, "import finished, \(app.importModel.arrivedCount) added")
        await wait(1200)
        snap(ArrivingScreen(model: model, app: app, grid: grid, elapsed: Date().timeIntervalSince(began), eta: eta), "arriving-full")
        check(stable, "no tile that was shown ever moved or changed (append only)")
        check(grid.count > 0, "\(grid.count) pictures in the grid")
        check(fixture.requests() >= 3, "the reader paged the board: \(fixture.requests()) feed requests")
        check(opened.isEmpty, "no browser was opened: \(opened)")
        grid.stop()

        // Landing: a hold, then the library on the first board's collection, as a calm grid
        await until(8) { app.onboarding == nil }
        check(app.onboarding == nil, "onboarding ended by itself")
        if case .collection = app.source { check(true, "first collection open") } else { check(false, "first collection open (source \(app.source))") }
        check(app.viewMode == .grid, "the library opens as a grid")
        check(OnboardingState.load(UserDefaults(suiteName: "xyz.arjoon.grails.onboarding-demo")!).done, "finished is remembered")
        check(app.toast?.hasPrefix("Imported") == true, "toast: \(app.toast ?? "none")")
        // the welcome: the tiles settle (a tick the grid answers), then the card
        let tick = app.settleTick
        app.greetAfterOnboarding()
        check(app.settleTick == tick + 1 && app.welcome == nil, "settling starts at once and the card waits for it")
        await until(4) { app.welcome != nil }
        check(app.welcome?.library == app.libraryName, "the welcome card follows with the library's name: \(app.welcome?.library ?? "none")")
        snap(ZStack { WelcomeCard(model: app, request: app.welcome ?? WelcomeRequest(library: "Library")) }, "welcome")
        app.welcome = nil
        fixture.stop()
        say(failed ? "FAIL" : "PASS")
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_DEMO_QUIT"] != nil { NSApp.terminate(nil) }
    }

    /// The view as an image, light and dark.
    private func snap<V: View>(_ view: V, _ name: String) { snap({ _ in view }, name) }

    private func snap<V: View>(_ make: (Bool) -> V, _ name: String, size: CGSize? = nil) {
        let size = size ?? self.size
        for (scheme, suffix) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let content = make(scheme == .dark)
                .frame(width: size.width, height: size.height)
                .background(Ink.canvas)
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: content)
            r.scale = 1
            guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(dir)/snap-\(name)-\(suffix).png"))
        }
    }
}

extension OnboardingDemo {
    /// Median and p95 milliseconds for a frame in the middle of a transition, at two window sizes, and the work done while a painting holds.
    func bench(_ engine: PaintingWallEngine) -> String {
        var lines: [String] = []
        for (label, size) in [("1280x800", CGSize(width: 1280, height: 800)), ("2560x1600", CGSize(width: 2560, height: 1600))] {
            for i in 0..<2 { engine.prepare(i, size: size) }
            var times: [Double] = []
            for k in 0..<60 {
                let t = PaintingWall.period + PaintingWall.transition * (0.2 + 0.6 * Double(k) / 60)
                let start = CFAbsoluteTimeGetCurrent()
                _ = engine.frame(size: size, t: t, dark: true, reduceMotion: false)
                times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            times.sort()
            lines.append("bench \(label): transition frame median \(String(format: "%.2f", times[30])) ms, p95 \(String(format: "%.2f", times[56])) ms")
        }
        return lines.joined(separator: "\n")
    }
}


extension OnboardingDemo {
    /// How much of the picture changes while a painting holds: the share of pixels that differ after 1 s and after 3 s (should be a few percent).
    func shimmerReport(_ engine: PaintingWallEngine) -> String {
        func bytes(_ t: Double) -> [UInt8]? {
            guard let f = engine.frame(size: size, t: t, dark: true, reduceMotion: false), let data = f.base.dataProvider?.data else { return nil }
            return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
        }
        guard let a = bytes(8), let b = bytes(9), let c = bytes(11), a.count == b.count, a.count == c.count else { return "shimmer: no frames" }
        func share(_ x: [UInt8], _ y: [UInt8]) -> Double {
            var d = 0, n = 0
            var i = 0
            while i + 3 < x.count { if x[i] != y[i] || x[i + 1] != y[i + 1] || x[i + 2] != y[i + 2] || x[i + 3] != y[i + 3] { d += 1 }; n += 1; i += 4 }
            return Double(d) / Double(max(n, 1))
        }
        return "shimmer: \(String(format: "%.1f", share(a, b) * 100)) % of pixels differ after 1 s, \(String(format: "%.1f", share(a, c) * 100)) % after 3 s"
    }
}
