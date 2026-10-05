import AppKit
import AVFoundation
import GrailsKit

/// Dev only: `GRAILS_HOVER_DEMO=<dir>` (with `GRAILS_LIBRARY=<dir>/Lib.grails GRAILS_INDEX_PATH=<dir>/index.sqlite`, and
/// `GRAILS_HOVER_DEMO_QUIT=1` to quit after). Seeds a small library with real short clips, then drives hover on the grid and the
/// canvas with synthetic pointer events delivered straight to the views (nothing goes through the window server, so nothing
/// else on the Mac is touched) and writes `result.txt` (PASS / FAIL) with CPU and memory readings.
@MainActor
struct HoverVideoDemo {
    let app: AppModel
    let dir: String

    // MARK: Seed

    static let clips: [(name: String, ext: String, w: Int, h: Int, seconds: Double, hue: CGFloat)] = [
        ("Clip A", "mp4", 640, 360, 3, 0.02), ("Clip B", "mp4", 640, 360, 3, 0.33), ("Clip C", "mov", 480, 480, 2, 0.58),
        ("Clip D", "mp4", 360, 640, 3, 0.80),
    ]

    /// A throwaway library: four short clips (H.264, 30 fps, a bar sweeping across a coloured field) and two pictures.
    static func seed(library url: URL) async {
        let src = url.deletingLastPathComponent().appendingPathComponent("hover-src")
        try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let index = ProcessInfo.processInfo.environment["GRAILS_INDEX_PATH"].flatMap { try? LibraryIndex(path: URL(fileURLWithPath: $0)) }
        guard let store = try? LibraryStore.create(at: url, name: "Hover Demo", index: index, userHandle: "demo") else { return }
        var files: [URL] = []
        for c in clips {
            let f = src.appendingPathComponent("\(c.name).\(c.ext)")
            try? FileManager.default.removeItem(at: f)
            if (try? await writeClip(to: f, type: c.ext == "mov" ? .mov : .mp4, width: c.w, height: c.h, seconds: c.seconds, hue: c.hue)) != nil { files.append(f) }
        }
        for (i, hue) in [0.12, 0.66].enumerated() {
            let f = src.appendingPathComponent("Picture \(i + 1).png")
            if let data = picture(hue: hue) { try? data.write(to: f); files.append(f) }
        }
        for f in files { _ = try? await store.addItem(fileAt: f) }
    }

    static func writeClip(to url: URL, type: AVFileType, width: Int, height: Int, seconds: Double, hue: CGFloat) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * 30)
        let bg = NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1).cgColor
        for i in 0..<frames {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pb = buffer else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let x = CGFloat(i) / CGFloat(frames) * CGFloat(width)
                ctx.setFillColor(.white); ctx.fill(CGRect(x: x - 20, y: 0, width: 40, height: CGFloat(height)))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    static func picture(hue: CGFloat) -> Data? {
        guard let ctx = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor(hue: hue, saturation: 0.5, brightness: 0.8, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        return ctx.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    // MARK: Run

    func run() async {
        var log: [String] = []
        var failed = false
        func say(_ s: String) { log.append(s); print("HOVER: \(s)"); try? log.joined(separator: "\n").write(toFile: dir + "/result.txt", atomically: true, encoding: .utf8) }
        func check(_ ok: Bool, _ what: String) { say((ok ? "ok   " : "FAIL ") + what); if !ok { failed = true } }
        func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func until(_ seconds: Double, _ cond: () -> Bool) async { for _ in 0..<Int(seconds * 20) where !cond() { await wait(50) } }

        let hv = HoverVideo.shared
        // the real availability check, except for the one file the demo pretends is online-only
        var onlineOnly: URL?
        let realAvailability = hv.availability
        hv.availability = { url in url == onlineOnly ? .cloudOnly : realAvailability(url) }
        hv.reduceMotion = { false }
        hv.enabled = { true }

        app.viewMode = .grid
        await until(20) { app.items.count >= 6 }
        check(app.items.count == 6, "library seeded: \(app.items.count) items (4 clips, 2 pictures)")
        func id(_ name: String) -> String? { app.items.first { $0.name.hasPrefix(name) }?.id }
        guard let a = id("Clip A"), let b = id("Clip B"), let c = id("Clip C"), let d = id("Clip D"), let pic = id("Picture 1"),
              let window = NSApp.windows.first(where: { $0.contentView.map(Self.findGrid) != nil }) ?? NSApp.windows.first,
              let content = window.contentView else {
            say("FAIL items or window missing"); finish(failed: true); return
        }
        await until(10) { Self.findGrid(content) != nil }
        await wait(800)
        guard let cv = Self.findGrid(content), let grid = cv.delegate as? GridView.Coordinator else { say("FAIL no grid"); finish(failed: true); return }

        func cell(_ id: String) -> ThumbCell? {
            cv.visibleItems().compactMap { $0 as? ThumbCell }.first { $0.itemID == id }
        }
        func gridPoint(_ id: String) -> NSPoint? {
            guard let cell = cell(id) else { return nil }
            return cv.convert(NSPoint(x: cell.view.frame.midX, y: cell.view.frame.midY), to: nil)
        }
        func moved(_ p: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
        }
        func hoverGrid(_ id: String) { if let p = gridPoint(id), let e = moved(p) { grid.hoverMoved(e) } }
        func hostedInGridCell(_ id: String) -> Bool { cell(id).map { hv.hostedIn === $0.view } ?? false }
        let names = [a: "A", b: "B", c: "C", d: "D", pic: "picture"]
        func playing() -> String { hv.playingID.flatMap { names[$0] } ?? "nothing" }

        // 1. dwell: a brief pass never starts; resting 250 ms starts the shared player on that tile
        let cpu0 = Self.cpuSeconds(), mem0 = Self.footprintMB()
        hoverGrid(a)
        await wait(120)
        check(hv.playingID == nil, "120 ms on A: still the picture (\(playing()))")
        hoverGrid(pic)
        await wait(400)
        check(hv.playingID == nil && hv.lastSkip == .notVideo, "a picture never plays (\(playing()), skip \(String(describing: hv.lastSkip)))")
        let t0 = CACurrentMediaTime()
        hoverGrid(a)
        await until(1) { hv.playingID != nil }
        let startedAfter = (CACurrentMediaTime() - t0) * 1000
        check(hv.playingID == a && startedAfter >= 240 && startedAfter < 400, "resting on A starts it after \(Int(startedAfter)) ms")
        check(hostedInGridCell(a), "the player sits in A's cell")
        await until(2) { (hv.player?.rate ?? 0) > 0 }
        check((hv.player?.rate ?? 0) > 0 && hv.player?.isMuted == true, "A plays, muted")
        if let cellA = cell(a) {
            let r = cv.convert(cellA.view.bounds, from: cellA.view)
            let fits = abs(hv.playerLayer.frame.width - r.width) < 1 && abs(hv.playerLayer.frame.height - r.height) < 1
            check(fits, "player layer covers the tile: \(hv.playerLayer.frame.size) vs \(r.size)")
        }
        let ct = hv.player.map { CMTimeGetSeconds($0.currentTime()) } ?? -1
        check(ct >= 0.55 && ct < 1.2, "starts on the thumbnail's frame (0.6 s in): at \(String(format: "%.2f", ct)) s")
        if let fi = hv.fadeLog.last { say("fade-in began \(Int((fi.1 - t0) * 1000)) ms after the pointer arrived (\(Int(HoverPreview.fadeIn * 1000)) ms ease-out)") }

        // 2. CPU and memory while it plays
        let c1 = Self.cpuSeconds(), w1 = CACurrentMediaTime()
        await wait(3000)
        let playCPU = (Self.cpuSeconds() - c1) / (CACurrentMediaTime() - w1) * 100
        let advanced = hv.player.map { CMTimeGetSeconds($0.currentTime()) } ?? 0
        check(hv.playingID == a, "A keeps playing and loops (clock at \(String(format: "%.2f", advanced)) s of 3 s; stops so far: \(hv.stopLog))")
        say(String(format: "CPU while one preview plays: %.1f%% of one core (app process; hardware decode may also show in VTDecoderXPCService); footprint %.0f MB → %.0f MB", playCPU, mem0, Self.footprintMB()))

        // 3. coordinates survive a scroll and a zoom step while it plays (programmatic: no scroll event, so it keeps playing)
        if let scroll = cv.enclosingScrollView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y + 30))
            scroll.reflectScrolledClipView(scroll.contentView)
            await wait(100)
            check(hostedInGridCell(a) && hv.playingID == a, "after a 30 pt scroll the player is still in A's cell")
        }
        app.zoom(by: 1.2)
        await wait(600)
        if let cellA = cell(a) {
            check(hostedInGridCell(a) && abs(hv.playerLayer.frame.width - cellA.view.bounds.width) < 0.5, "after a zoom step the player follows A (\(Int(hv.playerLayer.frame.width)) pt wide tile)")
        } else { check(false, "A's cell after a zoom step") }

        // 4. leaving stops at once; nothing keeps running
        hoverGrid(pic)
        check(hv.playingID == nil && hv.player?.rate == 0, "moving off A stops it at once")
        await wait(250)
        check(hv.player?.currentItem == nil && hv.hostedIn == nil, "after the fade the file is let go and the player is out of the tile")
        let c2 = Self.cpuSeconds(), w2 = CACurrentMediaTime()
        await wait(2000)
        let idleCPU = (Self.cpuSeconds() - c2) / (CACurrentMediaTime() - w2) * 100
        say(String(format: "CPU after leaving: %.1f%% of one core over 2 s; footprint %.0f MB", idleCPU, Self.footprintMB()))

        // 5. another tile takes over with the same player
        hoverGrid(a)
        await until(1) { hv.playingID == a }
        let playerA = hv.player.map(ObjectIdentifier.init)
        hoverGrid(b)
        check(hv.playingID == nil, "moving from A to B stops A at once")
        await until(1) { hv.playingID == b }
        check(hv.playingID == b && hostedInGridCell(b) && !hostedInGridCell(a), "B takes over after its own dwell")
        check(hv.playersMade == 1 && hv.player.map(ObjectIdentifier.init) == playerA, "one player for everything: \(hv.playersMade) made")

        // 6. scrolling stops it; moves right after a scroll don't arm a tile
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -12, wheel2: 0, wheel3: 0).flatMap { NSEvent(cgEvent: $0) }
        if let wheel { hv.handle(wheel) }
        check(hv.playingID == nil, "a scroll stops B")
        hoverGrid(b)
        await wait(400)
        check(hv.playingID == nil, "a move during the scroll's quiet period doesn't start anything")
        await wait(100)
        hoverGrid(b)
        await until(1) { hv.playingID == b }
        check(hv.playingID == b, "once quiet, resting starts B again")

        // 7. a press stops it (clicks, drags, marquee)
        if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: gridPoint(b) ?? .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { hv.handle(down) }
        check(hv.playingID == nil, "a press stops B")
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: gridPoint(b) ?? .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) { hv.handle(up) }

        // 8. the window resigning key, and the app going inactive, stop it
        hoverGrid(a); await until(1) { hv.playingID == a }
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(hv.playingID == nil, "window resigning key stops it")
        hoverGrid(b); await until(1) { hv.playingID == b }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        check(hv.playingID == nil, "app going inactive stops it")

        // 9. an online-only original never starts (and is never opened)
        let itemsBefore = hv.itemsMade
        if let s = app.summary(c) { onlineOnly = app.originalURL(for: s) }
        hoverGrid(c)
        await wait(500)
        check(hv.playingID == nil && hv.lastSkip == .cloudOnly && hv.itemsMade == itemsBefore, "online-only C keeps its still and is never opened (skip \(String(describing: hv.lastSkip)))")
        onlineOnly = nil

        // 10. Reduce Motion: never starts, and turning it on stops a preview
        hv.reduceMotion = { true }
        hoverGrid(d)
        await wait(500)
        check(hv.playingID == nil && hv.lastSkip == .reduceMotion, "Reduce Motion: D never starts")
        hv.reduceMotion = { false }
        hoverGrid(pic); hoverGrid(d)
        await until(1) { hv.playingID == d }
        check(hv.playingID == d, "without Reduce Motion D plays (\(playing()))")
        hv.reduceMotion = { true }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        check(hv.playingID == nil, "turning Reduce Motion on stops it")
        hv.reduceMotion = { false }

        // 11. the setting
        hv.enabled = { false }
        hoverGrid(pic); hoverGrid(a)
        await wait(500)
        check(hv.playingID == nil && hv.lastSkip == .disabled, "Settings ▸ Play videos on hover off: nothing plays")
        hv.enabled = { true }

        // 12. switching to the canvas while a preview plays stops it; the canvas plays on hover too
        hoverGrid(pic); hoverGrid(a)
        await until(1) { hv.playingID == a }
        app.viewMode = .canvas
        await wait(1500)
        check(hv.playingID == nil, "switching to the canvas stops the grid's preview")
        guard let canvas = Self.findCanvas(content) else { say("FAIL no canvas"); finish(failed: true); return }
        canvas.fit(ids: nil, animated: false)
        await wait(300)
        func canvasPoint(_ id: String) -> NSPoint? {
            guard let p = canvas.placements[id] else { return nil }
            let r = canvas.screenRect(CGRect(x: p.x, y: p.y, width: p.w, height: p.h))
            return canvas.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
        }
        func hoverCanvas(_ id: String) { if let p = canvasPoint(id), let e = moved(p) { canvas.hoverMoved(e) } }
        func onCanvasTile(_ id: String) -> Bool { (hv.playerLayer.superlayer as? CanvasItemLayer)?.summary?.id == id }
        hoverCanvas(pic); hoverCanvas(b)
        await until(1) { hv.playingID == b }
        check(hv.playingID == b && onCanvasTile(b), "canvas: resting on B plays it in B's tile")
        canvas.pan(byScreen: 25, 10)
        await wait(100)
        if let tile = hv.playerLayer.superlayer { check(onCanvasTile(b) && hv.playerLayer.frame == tile.bounds, "canvas: after a pan the player still fills B's tile") }
        hoverCanvas(c)
        check(hv.playingID == nil, "canvas: moving to C stops B")
        await until(1) { hv.playingID == c }
        check(hv.playingID == c && onCanvasTile(c) && hv.playersMade == 1, "canvas: C takes over, still one player")
        if let e = moved(canvas.convert(NSPoint(x: 4, y: 4), to: nil)) { canvas.hoverMoved(e) }
        check(hv.playingID == nil, "canvas: moving onto empty board stops it")

        // 13. nothing left running
        await wait(1500)
        check(hv.player?.rate == 0 && hv.player?.currentItem == nil && hv.hostedIn == nil, "at rest: player paused, no file open, not in any tile")
        let c3 = Self.cpuSeconds(), w3 = CACurrentMediaTime()
        await wait(2000)
        say(String(format: "CPU at rest at the end: %.1f%% of one core; footprint %.0f MB (start %.0f MB); demo used %.1f s CPU", (Self.cpuSeconds() - c3) / (CACurrentMediaTime() - w3) * 100,
                   Self.footprintMB(), mem0, Self.cpuSeconds() - cpu0))
        say("players made: \(hv.playersMade), files opened: \(hv.itemsMade)")
        app.viewMode = .grid
        say(failed ? "FAIL" : "PASS")
        finish(failed: failed)
    }

    private func finish(failed: Bool) {
        if ProcessInfo.processInfo.environment["GRAILS_HOVER_DEMO_QUIT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    static func findGrid(_ v: NSView) -> GrailsCollectionView? {
        if let g = v as? GrailsCollectionView { return g }
        for s in v.subviews { if let g = findGrid(s) { return g } }
        return nil
    }

    static func findCanvas(_ v: NSView) -> CanvasNSView? {
        if let g = v as? CanvasNSView { return g }
        for s in v.subviews { if let g = findCanvas(s) { return g } }
        return nil
    }

    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
