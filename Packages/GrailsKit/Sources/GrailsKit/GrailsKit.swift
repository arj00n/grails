/// Library-wide constants.
public enum GrailsKit {
    public static let schemaVersion = 1
    public static let libraryExtension = "grails"
    /// Libraries made before the app was renamed end in this; they open exactly the same.
    public static let legacyLibraryExtensions: Set<String> = ["stash"]
    public static func isLibraryExtension(_ ext: String) -> Bool { ext == libraryExtension || legacyLibraryExtensions.contains(ext) }
}
