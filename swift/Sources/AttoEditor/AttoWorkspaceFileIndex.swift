import Foundation

@MainActor
final class AttoWorkspaceFileIndex {
    struct Entry: Hashable {
        let url: URL
        let relativePath: String
    }

    private(set) var rootURL: URL
    private var cached: [Entry] = []
    private var isBuilt: Bool = false

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func setRootURL(_ url: URL) {
        rootURL = url.standardizedFileURL
        cached = []
        isBuilt = false
    }

    func entries() -> [Entry] {
        if isBuilt { return cached }
        rebuild()
        return cached
    }

    func rebuild() {
        let fm = FileManager.default
        let root = rootURL.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : (root.path + "/")

        var out: [Entry] = []
        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            if name == ".git" || name == "target" || name == ".build" {
                enumerator?.skipDescendants()
                continue
            }

            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if rv?.isDirectory == true {
                continue
            }
            guard rv?.isRegularFile == true else {
                continue
            }

            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            let rel = String(path.dropFirst(rootPath.count))
            out.append(Entry(url: url.standardizedFileURL, relativePath: rel))
        }

        // Stable display order when query is empty.
        out.sort { a, b in
            a.relativePath.localizedCaseInsensitiveCompare(b.relativePath) == .orderedAscending
        }

        cached = out
        isBuilt = true
    }
}

