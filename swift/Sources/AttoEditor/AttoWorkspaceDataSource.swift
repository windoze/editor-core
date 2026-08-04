import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoWorkspaceDataSource {
    private(set) var rootURL: URL
    private(set) var fileIndex: AttoWorkspaceFileIndex
    private var recentFiles: [URL] = []
    private let coreDocumentsProvider: () -> MultiDocumentEditorUI?

    init(
        rootURL: URL,
        coreDocumentsProvider: @escaping () -> MultiDocumentEditorUI?
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileIndex = AttoWorkspaceFileIndex(rootURL: rootURL)
        self.coreDocumentsProvider = coreDocumentsProvider
    }

    func setRootURL(_ url: URL) {
        rootURL = url.standardizedFileURL
        fileIndex.setRootURL(url)
        recentFiles = []
        if supportsCoreRecentFiles {
            try? coreDocumentsProvider()?.clearRecentFiles()
        }
    }

    func workspaceFileEntries() -> [AttoWorkspaceFileIndex.Entry] {
        if let coreIndexEntries = refreshedCoreProjectFileIndexEntries() {
            return coreIndexEntries
        }
        if let coreEntries = coreWorkspaceFileEntries() {
            return coreEntries
        }
        return fileIndex.entries()
    }

    func workspaceFileEntries(matching query: String, maxResults: UInt32 = 200) -> [AttoWorkspaceFileIndex.Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coreMatches = coreProjectFileIndexEntries(matching: q, maxResults: maxResults) {
            return coreMatches
        }
        let entries = workspaceFileEntries()
        guard q.isEmpty == false else {
            return Array(entries.prefix(Int(maxResults)))
        }
        return entries
            .filter { $0.relativePath.localizedCaseInsensitiveContains(q) }
            .prefix(Int(maxResults))
            .map { $0 }
    }

    func rememberRecentFile(_ url: URL) {
        let u = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == u }
        recentFiles.insert(u, at: 0)
        if recentFiles.count > 20 {
            recentFiles.removeLast(recentFiles.count - 20)
        }
        if supportsCoreRecentFiles {
            try? coreDocumentsProvider()?.rememberRecentFileURI(u.absoluteString)
        }
    }

    func recentFileURLs() -> [URL] {
        if let coreRecentFiles = coreRecentFileURLs() {
            return coreRecentFiles
        }
        return recentFiles
    }

    func restoreRecentFiles(filePaths: [String], fileManager: FileManager = .default) {
        var out: [URL] = []
        var seen: Set<String> = Set()

        for path in filePaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let key = url.path
            if seen.contains(key) { continue }
            seen.insert(key)
            if fileManager.fileExists(atPath: url.path) == false { continue }
            out.append(url)
            if out.count >= 20 { break }
        }

        recentFiles = out
        if supportsCoreRecentFiles {
            try? coreDocumentsProvider()?.restoreRecentFileURIs(
                out.map { $0.standardizedFileURL.absoluteString }
            )
        }
    }

    func rememberRecentProjectRoot(_ url: URL) {
        guard supportsCoreRecentProjects else { return }
        try? coreDocumentsProvider()?.rememberRecentProjectURI(
            url.standardizedFileURL.absoluteString
        )
    }

    func recentProjectURLs() -> [URL] {
        coreRecentProjectURLs() ?? []
    }

    func restoreRecentProjectURIs(_ uris: [String], fileManager: FileManager = .default) {
        guard supportsCoreRecentProjects else { return }

        var out: [String] = []
        var seen: Set<String> = []
        for uri in uris {
            let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  url.isFileURL
            else {
                continue
            }

            let standardized = url.standardizedFileURL
            guard Self.directoryExists(at: standardized, fileManager: fileManager) else {
                continue
            }

            let normalized = standardized.absoluteString
            guard seen.contains(normalized) == false else { continue }
            seen.insert(normalized)
            out.append(normalized)
            if out.count >= 20 { break }
        }

        try? coreDocumentsProvider()?.restoreRecentProjectURIs(out)
    }

    func sessionWorkspaceRootURL(fallback: URL) -> URL {
        if let coreRoot = coreWorkspaceRootURL() {
            return coreRoot
        }
        return fallback.standardizedFileURL
    }

    private var supportsCoreRecentFiles: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentRecentFiles) ?? false
    }

    private var supportsCoreRecentProjects: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentRecentProjects) ?? false
    }

    private var supportsCoreProjectFileIndex: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentProjectFileIndex) ?? false
    }

    private var supportsCoreProjectFileIndexQuery: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentProjectFileIndexQuery) ?? false
    }

    private var supportsCoreWorkspaceFileList: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentWorkspaceFileList) ?? false
    }

    private var supportsCoreWorkspaceFileScanOptions: Bool {
        coreDocumentsProvider()?.library.featureFlags.contains(.multiDocumentWorkspaceFileScanOptions) ?? false
    }

    private func coreRecentFileURLs() -> [URL]? {
        guard supportsCoreRecentFiles,
              let entries = try? coreDocumentsProvider()?.recentFiles()
        else {
            return nil
        }

        return entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }

    private func coreRecentProjectURLs() -> [URL]? {
        guard supportsCoreRecentProjects,
              let entries = try? coreDocumentsProvider()?.recentProjects()
        else {
            return nil
        }

        return entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }

    private func refreshedCoreProjectFileIndexEntries() -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreProjectFileIndex,
              let snapshot = try? coreDocumentsProvider()?
                  .refreshProjectFileIndexEnvelope()
                  .projectFileIndexSnapshot()
        else {
            return nil
        }

        return workspaceFileEntries(from: snapshot.files)
    }

    private func coreProjectFileIndexEntries(
        matching query: String,
        maxResults: UInt32
    ) -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreProjectFileIndexQuery,
              let coreDocuments = coreDocumentsProvider()
        else {
            return nil
        }

        _ = try? coreDocuments.refreshProjectFileIndexEnvelope().projectFileIndexSnapshot()
        guard let results = try? coreDocuments
            .queryProjectFileIndexEnvelope(query: query, maxResults: maxResults)
            .projectFileIndexQueryResults()
        else {
            return nil
        }
        return workspaceFileEntries(from: results)
    }

    private func coreWorkspaceFileEntries() -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreWorkspaceFileList,
              let coreDocuments = coreDocumentsProvider()
        else {
            return nil
        }

        let entries: [EcuWorkspaceFileEntry]?
        if supportsCoreWorkspaceFileScanOptions {
            entries = try? coreDocuments
                .listWorkspaceFilesEnvelope(scanOptions: EcuWorkspaceFileScanOptions())
                .workspaceFileEntries()
        } else {
            entries = try? coreDocuments
                .listWorkspaceFilesEnvelope()
                .workspaceFileEntries()
        }
        guard let entries else { return nil }
        return workspaceFileEntries(from: entries)
    }

    private func workspaceFileEntries(from entries: [EcuWorkspaceFileEntry]) -> [AttoWorkspaceFileIndex.Entry] {
        entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return AttoWorkspaceFileIndex.Entry(
                url: url.standardizedFileURL,
                relativePath: entry.relativePath
            )
        }
    }

    private func workspaceFileEntries(from entries: [EcuProjectFileIndexQueryResult]) -> [AttoWorkspaceFileIndex.Entry] {
        entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return AttoWorkspaceFileIndex.Entry(
                url: url.standardizedFileURL,
                relativePath: entry.relativePath
            )
        }
    }

    private func coreWorkspaceRootURL() -> URL? {
        guard let roots = try? coreDocumentsProvider()?.snapshot().workspaceRoots else {
            return nil
        }

        for root in roots {
            guard let url = URL(string: root), url.isFileURL else { continue }
            return url.standardizedFileURL
        }
        return nil
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
