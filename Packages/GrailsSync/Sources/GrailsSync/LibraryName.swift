import Foundation

public enum LibraryNameError: Error, Equatable, Sendable {
    case malformed
}

public enum LibraryName {
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public static func read(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    /// A reload that finished before a rename must not paint the old name back over the live one.
    /// `pending` is the name already shown. It stays until the file and the store both catch up, and it stays while both of them are still the previous name.
    public static func kept(current: String, reloaded: String, live: String, pending: String? = nil) -> String {
        if let pending {
            if reloaded == pending && live == pending { return pending }
            if reloaded != pending && live != pending { return pending }
        }
        return reloaded == live ? reloaded : current
    }

    public static func apply(_ data: Data, name: String) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibraryNameError.malformed
        }
        object["name"] = name
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public enum RenameProblem {
    public static func message(for error: Error) -> String {
        if let failure = error as? SyncFailure, failure == .notAllowed {
            return "Only an owner or admin can rename this library"
        }
        if let s3 = error as? S3Error {
            switch s3 {
            case .preconditionFailed:
                return "The bucket rejected the rename (412). Try again."
            case .notFound:
                return "The library is not in the bucket yet."
            case .status(let code, _):
                return "The bucket rejected the rename (\(code))."
            case .badResponse:
                return "The bucket sent a bad response."
            }
        }
        if error is LibraryNameError {
            return "The library file could not be read."
        }
        if error is URLError {
            return "Couldn't reach the bucket."
        }
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { return "Couldn't rename the library." }
        return "Couldn't rename the library. \(detail)"
    }
}
