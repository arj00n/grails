import Foundation

/// Deleting a library is two steps: the bucket's objects, then this Mac's credentials for it.
public enum LibraryDeletion {
    /// Forgets the credentials only after the remote delete succeeds. A failed delete throws and keeps them, so the
    /// library, still in the bucket, stays reachable from this Mac and the delete can be retried.
    public static func run(
        isolation: isolated (any Actor)? = #isolation,
        delete: () async throws -> Void,
        forget: () -> Void
    ) async throws {
        try await delete()
        forget()
    }
}
