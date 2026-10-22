import Foundation

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    // Saves and pairing stay on the loopback HTTP API, so this method must not become a second protocol.
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
