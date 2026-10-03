import Foundation

public enum FolderScanner {
    /// Files to import for a drop or open panel: plain files pass through, folders are walked recursively.
    /// Hidden files and the insides of packages (.app, …) and `.stash` libraries are skipped. Order is stable (sorted by path
    /// within each folder) so imports are reproducible.
    public static func expandFiles(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue else { out.append(url); continue }
            guard let walker = fm.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var found: [URL] = []
            while let f = walker.nextObject() as? URL {
                let values = try? f.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                // Never import a Stash library into another one, even before .stash is a registered package type.
                if values?.isDirectory == true, f.pathExtension == StashKit.libraryExtension { walker.skipDescendants(); continue }
                if values?.isRegularFile == true { found.append(f) }
            }
            out.append(contentsOf: found.sorted { $0.path < $1.path })
        }
        return out
    }
}
