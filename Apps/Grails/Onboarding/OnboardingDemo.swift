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

        // Hello: the field develops from the top left, the name types on, the pointer stirs it
        let centre = HelloFrame<EmptyView>.centre(size)
        for (name, t, pointer) in [("0000", 0.05, nil), ("0450", 0.45, nil), ("0900", 0.9, nil), ("1300", 1.3, nil), ("2000", 2.0, nil),
                                   ("pointer", 3.0, CGPoint(x: 330, y: 260))] as [(String, Double, CGPoint?)] {
            snap({ dark in
                HelloFrame(t: t, wall: {
                    if let img = AsciiWallView.render(size: size, t: t, pointer: pointer, dark: dark, centre: centre) { Image(decorative: img, scale: 1).resizable() }
                })
            }, "hello-\(name)")
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

    private func snap<V: View>(_ make: (Bool) -> V, _ name: String) {
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

