import Foundation

/// 持久化到磁盘的 AttoEditor 会话快照（Swift 侧）。
///
/// 说明：
/// - 只存 UI/宿主侧状态（窗口、目录、tab 列表等），不涉及 Rust 内核数据结构。
/// - schemaVersion 用于未来做向后兼容迁移。
struct AttoSessionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var savedAt: Date
    var activeWindowIndex: Int?
    var windows: [AttoWindowSnapshot]
}

struct AttoWindowSnapshot: Codable, Equatable, Sendable {
    var workspaceRootPath: String
    var frame: AttoWindowFrameSnapshot?
    var sidebarCollapsed: Bool
    var selectedTabIndex: Int?
    var tabs: [AttoTabSnapshot]
    var recentFilePaths: [String]
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
}
