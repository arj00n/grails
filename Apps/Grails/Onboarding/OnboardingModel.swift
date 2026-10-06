import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// First run: Hello → Choose (import boards, or start empty) → Paste → Arriving → the library. Each step has one main action. The library's
/// location and the person's name are decided for them (this Mac, their account name) unless they ask to change them.
@MainActor @Observable
final class OnboardingModel {
    enum Choice: Hashable { case thisMac, root(String), found(String), other, link }

    typealias Step = OnboardingState.Step

    private(set) var step: Step
    var handle: String
    var choice: Choice = .thisMac
    var linkText = ""
    private(set) var roots: [SyncedRoot] = []
    private(set) var found: [FoundLibrary] = []
    private(set) var otherURL: URL?
    private(set) var busy = false
    private(set) var problem: String?
    /// The team library set-up, shown over Choose.
    private(set) var teamSetup = false
    /// Someone who finished this before and is back because their library's folder is gone: no hello, no import.
    let returning: Bool
    let seed: UInt64

    weak var app: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var state: OnboardingState
    /// Dev demos: where "This Mac" is, and the home folder scanned for synced folders.
    @ObservationIgnored var thisMac = AppModel.defaultLibraryURL
    @ObservationIgnored var home = FileManager.default.homeDirectoryForCurrentUser

    init(app: AppModel, defaults: UserDefaults = .standard, resuming: Bool = false) {
        self.app = app
        self.defaults = defaults
        var s = OnboardingState.load(defaults)
        returning = s.done && !resuming
        if returning { s = OnboardingState() }
        state = s
        step = resuming ? s.step : (returning ? .whereIt : .hello)
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_CHOOSE"] != nil { step = .choose }      // dev: look at Choose without clicking through Hello
        handle = Handle.normalize(s.handle.isEmpty ? NSUserName() : s.handle)
        seed = Self.seed(for: NSUserName())
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_BACKTEST"] != nil {
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { e in print("BACKTEST mouse", e.type == .leftMouseDown ? "down" : "up", e.locationInWindow, "clickCount", e.clickCount); fflush(stdout); return e }
        }
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_BACKTEST"] != nil {                   // dev: Get Started, Import boards, then Back, logging each step
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2)); self?.start()
                try? await Task.sleep(for: .seconds(2)); self?.thisMac = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BackTest-\(UUID().uuidString.prefix(6)).grails"); if ProcessInfo.processInfo.environment["GRAILS_BACKTEST_REMEMBER"] == nil { self?.remember = false }; self?.importBoards()
                try? await Task.sleep(for: .seconds(14)); print("BACKTEST at paste? step=\(String(describing: self?.step)) busy=\(self?.busy ?? false) problem=\(self?.problem ?? "-") store=\(self?.app?.store != nil)"); fflush(stdout)
                if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_BACKTEST"] != "paste" { self?.back() }      // "paste": stop here and let a real click do it
                try? await Task.sleep(for: .seconds(4)); print("BACKTEST after back: step=\(String(describing: self?.step)) store=\(self?.app?.store != nil)"); fflush(stdout)
            }
        }
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_AUTOSTART"] != nil {                    // dev: press Get Started after 3 s, as a person would
            Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(3)); self?.start() }
        }
    }

    /// A stable number from the person's account name, so their wall is theirs.
    static func seed(for name: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    // MARK: Moving between steps

    func go(_ new: Step, duration: Double = Motion.standard) {
        guard new != step else { return }
        let curve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : duration)
        withAnimation(curve) { step = new }
        state.step = new
        state.save(defaults)
    }

    func openTeamSetup() { withAnimation(.easeOut(duration: Motion.standard)) { teamSetup = true } }

    /// Set-up finished or dismissed: a library that got made ends onboarding (a team library is there to be filled by the team), otherwise back to Choose.
    func closeTeamSetup() {
        withAnimation(.easeOut(duration: Motion.standard)) { teamSetup = false }
        if app?.store != nil { finish() }
    }

    func back() {
        if teamSetup { closeTeamSetup(); return }
        switch step {
        case .whereIt: if !returning { go(.choose) }
        case .paste: leavePaste()
        default: break      // once the library exists, going back would make a second one
        }
    }

    /// Back from the paste screen to Choose, so no route is a dead end. The empty library this run made on the way in is thrown away, so
    /// the next route (join one, another folder, a team library) starts clean; a library that was already there is left alone.
    func leavePaste() {
        guard let app, !app.importModel.isRunning else { return }
        let fresh = freshRoot
        freshRoot = nil
        // the screen goes back at once; the empty library is cleared away behind it (the next route waits for that to finish)
        go(.choose)
        discarding = Task { [weak self] in
            guard let self, let fresh, app.layout?.root.standardizedFileURL == fresh.standardizedFileURL else { return }
            if await app.discardFreshLibrary(forget: remember) {
                state.libraryPath = nil
                state.save(defaults)
            }
        }
    }

    /// The clearing away of the empty library, while it runs.
    @ObservationIgnored private var discarding: Task<Void, Never>?

    /// The folder a library was just made in by this run (nil if it was already there).
    @ObservationIgnored private var freshRoot: URL?

    /// Hello → Choose: 240 ms, the painting fades out and the two options fade in, with the name staying where it is.
    func start() { scan(); go(.choose, duration: 0.24) }

    /// What the person picks on Choose.
    func importBoards(paste: String? = nil) {
        guard app != nil else { return }
        pendingPaste = paste
        continueFromLibrary(next: .paste)
    }

    func startEmpty() { continueFromLibrary(next: .finish) }

    func join(_ library: FoundLibrary) { choice = .found(library.id); continueFromLibrary(next: .paste) }

    /// ⌘V on Choose: the clipboard's text goes into the import field, one action fewer.
    func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        importBoards(paste: (text?.isEmpty ?? true) ? nil : text)
    }

    /// The library's location was changed: back to Choose, which makes it when a choice is made.
    func confirmLocation() {
        if returning { continueFromLibrary(next: .finish) } else { go(.choose) }
    }

    @ObservationIgnored private var pendingPaste: String?

    // MARK: Library

    /// Looks for synced folders and for libraries already in them, off the main thread.
    func scan() {
        guard roots.isEmpty, found.isEmpty else { return }
        let home = home
        Task {
            let (r, f) = await Task.detached(priority: .userInitiated) { () -> ([SyncedRoot], [FoundLibrary]) in
                let r = SyncedRoots.detect(home: home)
                return (r, SyncedRoots.libraries(in: r))
            }.value
            roots = r
            found = f
        }
    }

    var chosenPath: String {
        switch choice {
        case .thisMac: Self.tilde(thisMac)
        case .root(let id): roots.first { $0.id == id }.map { Self.tilde($0.url) } ?? ""
        case .found(let id): found.first { $0.id == id }.map { Self.tilde($0.url) } ?? ""
        case .other: otherURL.map(Self.tilde) ?? ""
        case .link: ""
        }
    }

    /// The place in a word or two: "Pictures", "Google Drive", the folder's name.
    var thisMacLabel: String { Self.place(of: thisMac) }

    var chosenLabel: String {
        switch choice {
        case .thisMac: thisMacLabel
        case .root(let id): roots.first { $0.id == id }?.name ?? thisMacLabel
        case .found(let id): found.first { $0.id == id }.map { Self.place(of: $0.url) } ?? thisMacLabel
        case .other: otherURL.map(Self.place(of:)) ?? "Choose a folder"
        case .link: "A link"
        }
    }

    /// The folder a library sits in, by name ("~/Pictures/Grails Library.grails" → "Pictures").
    static func place(of library: URL) -> String {
        let parent = library.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? library.lastPathComponent : parent
    }

    static func tilde(_ url: URL) -> String { url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.treatsFilePackagesAsDirectories = false
        p.prompt = "Choose"
        guard p.runModal() == .OK, let url = p.url else { return }
        // a library goes in as it is; any other folder gets one inside it
        otherURL = FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) ? url : url.appendingPathComponent("Grails Library.grails", isDirectory: true)
        choice = .other
    }

    var canContinue: Bool {
        if busy || Handle.normalize(handle).isEmpty { return false }
        switch choice {
        case .other: return otherURL != nil
        case .link: return GrailsLink(text: linkText) != nil
        default: return true
        }
    }

    enum Next { case paste, finish }

    /// Opens or creates the library that is picked (this Mac unless they changed it). One that already has pictures ends onboarding.
    func continueFromLibrary(next: Next = .paste) {
        guard canContinue, let app, !busy else { return }
        busy = true
        problem = nil
        let pending = discarding
        defaults.set(Handle.normalize(handle), forKey: "userHandle")
        state.handle = Handle.normalize(handle)
        Task {
            await pending?.value
            await open(app, next: next)
            busy = false
        }
    }

    private func open(_ app: AppModel, next: Next) async {
        var url: URL?
        switch choice {
        case .thisMac: url = thisMac
        case .root(let id): url = roots.first { $0.id == id }?.url.appendingPathComponent("Grails Library.grails", isDirectory: true)
        case .found(let id): url = found.first { $0.id == id }?.url
        case .other: url = otherURL
        case .link:
            guard let link = GrailsLink(text: linkText) else { problem = "Not a Grails link"; return }
            url = found.first { AppModel.libraryID(at: $0.url) == link.library }?.url
            if url == nil {
                await app.openLink(link)
                guard app.store != nil, app.libraryID == link.library else { return }
                await opened(app, next: next)
                return
            }
        }
        guard let url else { return }
        let existed = FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path)
        await app.openOrCreate(at: url, remember: remember)
        freshRoot = existed ? nil : url
        guard app.store != nil else { problem = "Couldn't open that folder"; return }
        await opened(app, next: next)
    }

    private func opened(_ app: AppModel, next: Next) async {
        state.libraryPath = app.layout?.root.path
        let count = (try? await app.store?.index.count(ItemQuery())) ?? 0
        if count > 0 || returning || next == .finish { finish(); return }
        if let text = pendingPaste { app.importModel.ingest(text); pendingPaste = nil }
        go(.paste)
    }

    /// Dev demos leave the person's own preferences alone.
    @ObservationIgnored var remember = true

    // MARK: Import and after

    /// Import: the ticked boards run as one job; the screen follows to Arriving once it runs.
    func startImport() {
        guard let app else { return }
        app.importModel.opensFirstCollection = true
        app.importModel.start()
        if app.importModel.isRunning { go(.arriving) }
    }

    /// The import is done: wait until the library underneath is laid out on the first board's collection, hold on the finished screen for
    /// 600 ms, then fade into it (180 ms, no scale).
    func landWhenReady() {
        Task {
            for _ in 0..<100 where !(app?.importLandingReady ?? true) { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(600))
            finish()
        }
    }

    /// Leaves onboarding. An import still running carries on in the sidebar footer.
    func finish() {
        state.done = true
        state.step = .arriving
        state.save(defaults)
        app?.importModel.opensFirstCollection = false
        // the first thing the library shows is a calm grid, never a canvas that has to fit itself around items still arriving
        if app?.viewMode == .canvas { app?.viewMode = .grid }
        withAnimation(.easeOut(duration: Motion.standard)) { app?.onboarding = nil }
        if remember, !returning { app?.greetAfterOnboarding() }
    }
}
