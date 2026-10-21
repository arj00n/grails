import CoreServices
import Foundation

/// Watches a library folder with FSEvents and reports changed paths in batches. Sync clients (Google Drive, Dropbox)
/// deliver events late and sometimes not at all, so callers also run a periodic rescan as a safety net.
public final class LibraryWatcher: @unchecked Sendable {
    private let root: URL
    private let latency: TimeInterval
    private let onChange: @Sendable ([String]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "xyz.arjoon.grails.watcher")

    public init(root: URL, latency: TimeInterval = 0.4, onChange: @escaping @Sendable ([String]) -> Void) {
        self.root = root; self.latency = latency; self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }
        let box = Unmanaged.passRetained(CallbackBox(onChange))
        var ctx = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil, release: { info in
            if let info { Unmanaged<CallbackBox>.fromOpaque(info).release() }
        }, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            box.handler(Array(list.prefix(count)))
        }, &ctx, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { box.release(); return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private final class CallbackBox {
        let handler: @Sendable ([String]) -> Void
        init(_ h: @escaping @Sendable ([String]) -> Void) { handler = h }
    }
}
