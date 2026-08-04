import Foundation

/// 持久化到磁盘的 AttoEditor 会话快照（Swift 侧）。
///
/// 说明：
/// - 只存 UI/宿主侧状态（窗口、目录、tab 列表等），不直接序列化 Rust 内核数据结构。
/// - schemaVersion 用于未来做向后兼容迁移。
struct AttoSessionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var savedAt: Date
    var activeWindowIndex: Int?
    var recentProjectURIs: [String]
    var windows: [AttoWindowSnapshot]

    init(
        schemaVersion: Int,
        savedAt: Date,
        activeWindowIndex: Int?,
        recentProjectURIs: [String] = [],
        windows: [AttoWindowSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.activeWindowIndex = activeWindowIndex
        self.recentProjectURIs = recentProjectURIs
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case activeWindowIndex
        case recentProjectURIs
        case windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        activeWindowIndex = try container.decodeIfPresent(Int.self, forKey: .activeWindowIndex)
        recentProjectURIs = try container.decodeIfPresent([String].self, forKey: .recentProjectURIs) ?? []
        windows = try container.decode([AttoWindowSnapshot].self, forKey: .windows)
    }
}

struct AttoWindowSnapshot: Codable, Equatable, Sendable {
    var workspaceRootPath: String
    var workspaceRootURI: String?
    var frame: AttoWindowFrameSnapshot?
    var sidebarCollapsed: Bool
    var selectedTabIndex: Int?
    var tabs: [AttoTabSnapshot]
    var recentFilePaths: [String]

    func validatedWorkspaceRootURL(fileManager: FileManager = .default) -> URL? {
        if let workspaceRootURI,
           let url = URL(string: workspaceRootURI),
           url.isFileURL,
           Self.directoryExists(at: url.standardizedFileURL, fileManager: fileManager)
        {
            return url.standardizedFileURL
        }

        let pathURL = URL(fileURLWithPath: workspaceRootPath).standardizedFileURL
        guard Self.directoryExists(at: pathURL, fileManager: fileManager) else {
            return nil
        }
        return pathURL
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

struct AttoWindowFrameSnapshot: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct AttoTabSnapshot: Codable, Equatable, Sendable {
    var filePath: String
    var isPreview: Bool
    var showsMinimap: Bool?
    var paneCount: Int?
    var activePaneIndex: Int?
    var paneLayout: AttoPaneLayoutSnapshot?
    var isUntitled: Bool?
    var unsavedText: String?
}

struct AttoPaneLayoutSnapshot: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case leaf
        case split
    }

    enum Axis: String, Codable, Sendable {
        case horizontal
        case vertical
    }

    var kind: Kind
    var axis: Axis?
    var paneIndex: Int?
    var activePaneIndex: Int?
    var children: [AttoPaneLayoutSnapshot]?

    static func horizontalSplit(paneCount: Int, activePaneIndex: Int) -> AttoPaneLayoutSnapshot {
        let safePaneCount = max(1, paneCount)
        let safeActiveIndex = max(0, min(activePaneIndex, safePaneCount - 1))
        return AttoPaneLayoutSnapshot(
            kind: .split,
            axis: .horizontal,
            paneIndex: nil,
            activePaneIndex: safeActiveIndex,
            children: (0..<safePaneCount).map { paneIndex in
                AttoPaneLayoutSnapshot(
                    kind: .leaf,
                    axis: nil,
                    paneIndex: paneIndex,
                    activePaneIndex: nil,
                    children: nil
                )
            }
        )
    }

    var flattenedPaneCount: Int {
        switch kind {
        case .leaf:
            return 1
        case .split:
            let count = children?.reduce(0) { $0 + $1.flattenedPaneCount } ?? 0
            return max(1, count)
        }
    }

    var clampedActivePaneIndex: Int {
        let count = flattenedPaneCount
        return max(0, min(activePaneIndex ?? 0, count - 1))
    }
}
