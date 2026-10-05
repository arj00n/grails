import Foundation
import Network

/// Dev only: a stand-in for a Pinterest board on 127.0.0.1, so the in-app reader (a real web view) can be exercised without the network. It serves
/// a board page that holds a board id, and the board feed in pages of 100, ending with "-end-". Pictures are named for the fixture network.
final class CollectorFixture: @unchecked Sendable {
    private var listener: NWListener?
    let pins: Int
    private(set) var feedRequests = 0
    private let lock = NSLock()

    init(pins: Int) { self.pins = pins }

    func start() async throws -> UInt16 {
        let l = try NWListener(using: .tcp, on: .any)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        return try await withCheckedThrowingContinuation { cont in
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: if let p = l.port?.rawValue { l.stateUpdateHandler = nil; cont.resume(returning: p) }
                case .failed(let e): l.stateUpdateHandler = nil; cont.resume(throwing: e)
                default: break
                }
            }
            l.start(queue: .global())
        }
    }

    func stop() { listener?.cancel() }

    func requests() -> Int { lock.lock(); defer { lock.unlock() }; return feedRequests }

    private func handle(_ c: NWConnection) {
        c.start(queue: .global())
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { c.cancel(); return }
            let path = text.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let (type, body) = self.respond(to: path)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private func respond(to path: String) -> (String, Data) {
        if path.hasPrefix("/resource/BoardFeedResource/get/") {
            lock.lock(); feedRequests += 1; lock.unlock()
            var page = 0
            if let q = path.components(separatedBy: "data=").last?.removingPercentEncoding,
               let json = try? JSONSerialization.jsonObject(with: Data(q.utf8)) as? [String: Any],
               let options = json["options"] as? [String: Any], let bm = (options["bookmarks"] as? [String])?.first, bm.hasPrefix("p") { page = Int(bm.dropFirst()) ?? 0 }
            let size = 100, start = page * size, end = min(start + size, pins)
            let list: [[String: Any]] = (start..<max(start, end)).map { n in
                ["type": "pin", "id": "\(9000 + n)", "description": "Pin \(n)", "link": NSNull(), "pinner": ["username": "ana", "full_name": "Ana"],
                 "images": ["orig": ["url": "https://cdn.test/img\(n).png"]]]
            }
            let next = end >= pins ? "-end-" : "p\(page + 1)"
            let body = (try? JSONSerialization.data(withJSONObject: ["resource_response": ["data": list, "bookmark": next]])) ?? Data()
            return ("application/json", body)
        }
        // any board page: the id sits in text the way the real page embeds it
        return ("text/html", Data("<html><body><script>var s = \"board_id\\\",\\\"4242\\\"\";</script></body></html>".utf8))
    }
}
