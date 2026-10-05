import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// First run: Hello → Library → Import → Arriving. Each step has one main action; Esc goes back; Skip opens an empty library.
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
        step = resuming ? s.step : (returning ? .library : .hello)
        handle = Handle.normalize(s.handle.isEmpty ? NSUserName() : s.handle)
        seed = Self.seed(for: NSUserName())
    }

    /// A stable number from the person's account name, so their wall is theirs.
    static func seed(for name: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    // MARK: Moving between steps

    func go(_ new: Step) {
        guard new != step else { return }
        withAnimation(.easeOut(duration: Motion.standard)) { step = new }
        state.step = new
        state.save(defaults)
    }

    func back() {
        switch step {
        case .library: if !returning { go(.hello) }
        case .importing: break      // the library already exists; going back would make a second one
        default: break
        }
    }

    func start() { go(.library); scan() }

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
            if choice == .thisMac, let first = f.first { choice = .found(first.id) }
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

    /// Opens or creates the library that is picked. One that already has pictures ends onboarding; a new one goes on to Import.
    func continueFromLibrary() {
        guard canContinue, let app else { return }
        busy = true
        problem = nil
        defaults.set(Handle.normalize(handle), forKey: "userHandle")
        state.handle = Handle.normalize(handle)
        Task {
            await open(app)
            busy = false
        }
    }

    private func open(_ app: AppModel) async {
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
                await opened(app)
                return
            }
        }
        guard let url else { return }
        await app.openOrCreate(at: url, remember: remember)
        guard app.store != nil else { problem = "Couldn't open that folder"; return }
        await opened(app)
    }

    private func opened(_ app: AppModel) async {
        state.libraryPath = app.layout?.root.path
        let count = (try? await app.store?.index.count(ItemQuery())) ?? 0
        if count > 0 || returning { finish() } else { go(.importing) }
    }

    /// Dev demos leave the person's own preferences alone.
    @ObservationIgnored var remember = true

    // MARK: Import and after

    /// Import: the ticked boards run as one job, and the wall fills with what arrives.
    func startImport() {
        guard let app else { return }
        app.importModel.opensFirstCollection = true
        app.importModel.start()
        if app.importModel.isRunning { go(.arriving) }
    }

    /// Skip: an empty library on this Mac (or, past Library, the one that is open).
    func skip() {
        guard let app else { return }
        if app.store != nil { finish(); return }
        Task {
            await app.openOrCreate(at: thisMac, remember: remember)
            if app.store != nil { finish() }
        }
    }

    /// Leaves onboarding. An import still running carries on in the sidebar footer.
    func finish() {
        state.done = true
        state.step = .arriving
        state.save(defaults)
        app?.importModel.opensFirstCollection = false
        withAnimation(.easeOut(duration: Motion.standard)) { app?.onboarding = nil }
    }
}
