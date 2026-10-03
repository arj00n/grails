import AppKit
import WebKit

/// Renders a web page offscreen and returns it as a PNG (1280×960, so link cards are 4:3).
@MainActor
enum LinkSnapshotter {
    static func capture(url: URL, timeout: TimeInterval = 25) async -> Data? {
        let size = NSSize(width: 1280, height: 960)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()        // never share cookies or logins with a page we fetch
        let web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        // WebKit only paints views that live in a window, so park one far off-screen.
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }

        let loader = Loader()
        web.navigationDelegate = loader
        if url.isFileURL { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) } else { web.load(URLRequest(url: url, timeoutInterval: timeout)) }
        guard await loader.waitForLoad(timeout: timeout) else { return nil }
        try? await Task.sleep(for: .milliseconds(1200))      // let late images and fonts settle

        let snap = WKSnapshotConfiguration()
        snap.rect = NSRect(origin: .zero, size: size)
        snap.snapshotWidth = 1280
        guard let image = try? await web.takeSnapshot(configuration: snap), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    private final class Loader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var finished: Bool?

        /// Resolves true when the page finishes loading, false on failure or after `timeout` seconds.
        func waitForLoad(timeout: TimeInterval) async -> Bool {
            if let finished { return finished }
            return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                continuation = c
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    MainActor.assumeIsolated { self?.done(false) }
                }
            }
        }

        private func done(_ ok: Bool) {
            guard finished == nil else { return }
            finished = ok
            continuation?.resume(returning: ok)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done(false) }
    }
}
