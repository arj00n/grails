import CryptoKit
import Foundation

/// A member id that is the same on every Mac. It comes from the owner key plus the roster email, or the handle when there is no email.
public enum MemberIdentity {
    public static func deterministic(ownerKey: String?, email: String?, handle: String) -> String {
        let mail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seed: String
        if mail.contains("@") {
            seed = "email:\(ownerKey ?? ""):\(mail)"
        } else {
            seed = "handle:\(ownerKey ?? ""):\(Handle.normalize(handle))"
        }
        let digest = Data(SHA256.hash(data: Data(seed.utf8)))
        return digest.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
