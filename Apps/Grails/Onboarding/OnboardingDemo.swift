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

        // Hello: the paintings, the wave between them, the loupe, the plate with its caption
        let engine = PaintingWallEngine.shared
        check(engine != nil && engine!.specs.count == 14, "painting manifest loads: \(engine?.specs.count ?? 0) works")
        if let engine {
            for i in engine.specs.indices { engine.prepare(i, size: size) }
            engine.prepare(0, size: size, pixel: 1); engine.prepare(1, size: size, pixel: 1)
            func hello(_ name: String, t: Double, touches: [PaintingWall.Touch] = [], reduceMotion: Bool = false, size: CGSize = size, indices: Bool = true) {
                let sched = PaintingWall.schedule(t: t, count: engine.specs.count, reduceMotion: reduceMotion)
                let caption = engine.specs[PaintingWall.captionIndex(sched)].caption
                snap({ dark in
                    HelloFrame(t: t, size: size, caption: caption, wall: {
                        if let img = engine.render(size: size, t: t, dark: dark, touches: touches, reduceMotion: reduceMotion) { Image(decorative: img, scale: 1).resizable() }
                    })
                }, name, size: size)
            }
            for (name, t) in [("0000", 0.05), ("0450", 0.45), ("0900", 0.9), ("1300", 1.3)] { hello("hello-\(name)", t: t) }
            for i in engine.specs.indices { hello("hello-rest-\(engine.specs[i].id)", t: 8.0 * Double(i) + 4) }
            for (n, p) in [(25, 0.25), (50, 0.5), (75, 0.75)] { hello("hello-wave-\(n)", t: 8.0 + 1.6 * p) }
            hello("hello-loupe", t: 3, touches: (0..<8).map { PaintingWall.Touch(x: 450 - Double($0) * 9, y: 290 + Double($0) * 4, age: Double($0) * 0.06) })
            hello("hello-reduce-motion", t: 10, reduceMotion: true)
            say(bench(engine))
        }
        check(model.step == .hello, "starts on Hello")

        // Library: the synced drive shows up with the library already in it, and is preselected
        model.start()
        await until(5) { !model.found.isEmpty }
        await wait(300)
        check(model.roots.count == 1 && model.found.map(\.name) == ["Team Inspo"], "found the drive and the library in it: \(model.roots.map(\.name)) \(model.found.map(\.name))")
        check({ if case .found = model.choice { true } else { false } }(), "Found library is preselected")
        snap(ZStack { LibraryStep(model: model) }, "library")
        model.choice = .thisMac
        model.handle = Handle.normalize("Ana M")
        snap(ZStack { LibraryStep(model: model) }, "library-this-mac")
        model.continueFromLibrary()
        await until(10) { model.step == .importing }
        check(model.step == .importing && app.store != nil, "a new empty library goes on to Import")
        check(FileManager.default.fileExists(atPath: dir + "/This Mac.grails/library.json"), "library created on This Mac")

        // Import: paste a mixed list, then go
        app.importModel.ingest("""
        https://www.are.na/ana/demo-one and pinterest.com/ana/interiors/, plus https://www.are.na/demo
        also https://example.com/x and pinterest.com/anaprofile
        """)
        await until(10) { !app.importModel.stillChecking }
        app.importModel.setSelected("arena:other-one", true)
        snap(ZStack { ImportStep(model: model) }, "import")
        check(app.importModel.selectedItemCount > 0, "rows ready: \(app.importModel.selectedItemCount) items")
        model.startImport()
        check(model.step == .arriving, "Import goes on to Arriving")

        // Arriving: the wall takes the pictures as they land
        let wall = WallModel()
        let arrivingSlots = Mosaic.layout(seed: model.seed, size: ArrivingFrame.wall(size))
        wall.configure(slots: arrivingSlots, reserved: nil)
        var shots = 0
        var placed = Set<String>()
        while app.importModel.phase == .running, shots < 3 {
            await wait(250)
            fill(wall, &placed)
            snap(ArrivingScreen(model: model, app: app, wall: wall, slots: arrivingSlots, size: size, t: 10), "arriving-\(shots)")
            shots += 1
        }
        await until(30) { app.importModel.phase == .finished }
        check(app.importModel.phase == .finished, "import finished, \(app.importModel.arrivedCount) added")
        fill(wall, &placed)
        snap(ArrivingScreen(model: model, app: app, wall: wall, slots: arrivingSlots, size: size, t: 10), "arriving-full")
        check(wall.pictures.count > 0, "\(wall.pictures.count) pictures on the wall")

        // Finish: a hold, then the library, with the first board's collection open
        await until(5) { app.onboarding == nil }
        check(app.onboarding == nil, "onboarding ended by itself")
        if case .collection = app.source { check(true, "first collection open") } else { check(false, "first collection open (source \(app.source))") }
        check(OnboardingState.load(UserDefaults(suiteName: "xyz.arjoon.grails.onboarding-demo")!).done, "finished is remembered")
        check(app.toast?.hasPrefix("Imported") == true, "toast: \(app.toast ?? "none")")
        say(failed ? "FAIL" : "PASS")
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_DEMO_QUIT"] != nil { NSApp.terminate(nil) }
    }

    /// Every arrival so far, onto the wall.
    private func fill(_ wall: WallModel, _ placed: inout Set<String>) {
        guard let layout = app.layout else { return }
        for id in app.importModel.arrivals where placed.insert(id).inserted {
            guard let cg = ThumbnailLoader.decode(layout.thumbURL(id), maxPixel: 256) else { continue }
            wall.place((cg, Double(cg.width) / Double(max(cg.height, 1))), instant: true)
        }
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
    /// Median and p95 milliseconds for a frame in the middle of a wave, at two window sizes, and the work done while a painting holds.
    func bench(_ engine: PaintingWallEngine) -> String {
        var lines: [String] = []
        for (label, size) in [("1280x800", CGSize(width: 1280, height: 800)), ("2560x1600", CGSize(width: 2560, height: 1600))] {
            for i in 0..<2 { engine.prepare(i, size: size) }
            var times: [Double] = []
            for k in 0..<60 {
                let t = 8.0 + 1.6 * (0.2 + 0.6 * Double(k) / 60)
                let start = CFAbsoluteTimeGetCurrent()
                _ = engine.frame(size: size, t: t, dark: true, reduceMotion: false, touches: [])
                times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            times.sort()
            lines.append("bench \(label): wave frame median \(String(format: "%.2f", times[30])) ms, p95 \(String(format: "%.2f", times[56])) ms")
        }
        return lines.joined(separator: "\n")
    }
}

