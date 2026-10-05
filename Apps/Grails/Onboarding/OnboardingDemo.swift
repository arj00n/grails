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
