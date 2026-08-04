import Foundation

struct AttoSublimePackageResource: Equatable {
    let fileURL: URL
    let relativePath: String

    var displayName: String {
        relativePath
    }

    static func discover(
        in workspaceRootURL: URL,
        fileManager: FileManager = .default,
        limit: Int = 200
    ) -> [AttoSublimePackageResource] {
        guard let enumerator = fileManager.enumerator(
            at: workspaceRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var resources: [AttoSublimePackageResource] = []
        for case let url as URL in enumerator {
            guard shouldVisit(url: url) else {
                if hasHiddenPathComponent(url: url, rootURL: workspaceRootURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard isPackageResource(url: url) else { continue }
            resources.append(
                AttoSublimePackageResource(
                    fileURL: url.standardizedFileURL,
                    relativePath: relativePath(for: url, rootURL: workspaceRootURL)
                )
            )
            if resources.count >= limit { break }
        }

        return resources.sorted { lhs, rhs in
            lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func isPackageResource(url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.contains(".sublime-") { return true }

        switch url.pathExtension {
        case "tmLanguage", "tmPreferences", "plist", "json", "yaml", "yml":
            return url.pathComponents.contains("Packages")
        default:
            return false
        }
    }

    private static func shouldVisit(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]) else {
            return false
        }
        return values.isHidden != true || values.isRegularFile == true
    }

    private static func hasHiddenPathComponent(url: URL, rootURL: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count)
        return components.contains { $0.hasPrefix(".") }
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
