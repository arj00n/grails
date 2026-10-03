import AppKit
import QuartzCore

/// Dev tool: counts main-thread frame stalls while the grid is on screen.
/// Enabled with STASH_HITCH_REPORT=1; publishes `{frames, hitches, worstMs}` JSON as the label of an invisible
/// accessibility element ("hitch-report") once a second, which UI tests read (the test runner is sandboxed,
/// so a shared file doesn't work).
@MainActor
final class HitchMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0
    private var worst: Double = 0
    private var lastWrite: CFTimeInterval = 0
    let probe = NSView()
    nonisolated(unsafe) static weak var current: HitchMonitor?
    private var timings: [String: Double] = [:]
    private var activeUntil: CFTimeInterval = 0
    private var done = false
    private var phase = ""
    private var hitchesByPhase: [String: Int] = [:]

    static func make() -> HitchMonitor? {
        ProcessInfo.processInfo.environment["STASH_HITCH_REPORT"] == nil ? nil : HitchMonitor()
    }

    /// Records the worst duration (ms) seen for a named operation; shown in the report as `maxMs`.
    nonisolated static func record(_ name: String, since start: CFTimeInterval) {
        let ms = (CACurrentMediaTime() - start) * 1000
        DispatchQueue.main.async { MainActor.assumeIsolated { current?.timings[name] = max(current?.timings[name] ?? 0, ms) } }
    }

    private override init() {
        super.init()
        Self.current = self
        probe.setAccessibilityElement(true)
        probe.setAccessibilityRole(.staticText)
        probe.setAccessibilityIdentifier("hitch-report")
        probe.setAccessibilityLabel("{}")
    }

    func start(on view: NSView) {
        guard link == nil else { return }
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        defer { last = now }
        guard last > 0, now < activeUntil else { return }
        let ms = (now - last) * 1000
        frames += 1
        if ms > 33 { hitches += 1; hitchesByPhase[phase, default: 0] += 1 }
        worst = max(worst, ms)
        if now - lastWrite > 1 {
            lastWrite = now
            publish()
        }
    }

    /// Only frames shortly after scroll or zoom input are counted, so idle time can't hide or fake a hitch.
    func noteActivity() { activeUntil = CACurrentMediaTime() + 0.3 }

    func setPhase(_ p: String) { phase = p }

    func finish() { done = true; publish() }

    private func publish() {
        let by = hitchesByPhase.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        probe.setAccessibilityLabel("{\"frames\":\(frames),\"hitches\":\(hitches),\"worstMs\":\(Int(worst)),\"done\":\(done),\"byPhase\":{\(by)},\"maxMs\":{\(timings.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\(Int($0.value))" }.joined(separator: ","))}}")
    }

    /// Reset counters (called when a scroll test starts so idle time isn't counted).
    func reset() { frames = 0; hitches = 0; worst = 0; last = 0 }
}
