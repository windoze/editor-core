import AppKit
import Foundation

enum AttoAccessibilityID {
    static let editorArea = "AttoEditor.EditorArea"
    static let editorContentHost = "AttoEditor.EditorContentHost"
    static let editorEmptyState = "AttoEditor.EditorEmptyState"

    static let tabBar = "AttoEditor.TabBar"
    static let tabBarScrollView = "AttoEditor.TabBar.ScrollView"
    static let tabBarOverflowButton = "AttoEditor.TabBar.OverflowButton"
    static let tabBarEmptyLabel = "AttoEditor.TabBar.EmptyLabel"

    static func tabChip(_ id: UUID) -> String {
        "AttoEditor.TabBar.Tab.\(id.uuidString)"
    }

    static func tabTitle(_ id: UUID) -> String {
        "AttoEditor.TabBar.TabTitle.\(id.uuidString)"
    }

    static func tabCloseButton(_ id: UUID) -> String {
        "AttoEditor.TabBar.TabClose.\(id.uuidString)"
    }

    static func editorPane(_ id: UUID) -> String {
        "AttoEditor.EditorPane.\(id.uuidString)"
    }

    static func editorView(_ id: UUID) -> String {
        "AttoEditor.EditorView.\(id.uuidString)"
    }

    static let findReplaceBar = "AttoEditor.FindReplaceBar"
    static let findSearchField = "AttoEditor.FindReplace.SearchField"
    static let findReplaceField = "AttoEditor.FindReplace.ReplaceField"
    static let findCaseSensitiveButton = "AttoEditor.FindReplace.CaseSensitive"
    static let findWholeWordButton = "AttoEditor.FindReplace.WholeWord"
    static let findRegexButton = "AttoEditor.FindReplace.Regex"
    static let findMatchCountLabel = "AttoEditor.FindReplace.MatchCount"
    static let findPreviousButton = "AttoEditor.FindReplace.Previous"
    static let findNextButton = "AttoEditor.FindReplace.Next"
    static let findClearButton = "AttoEditor.FindReplace.Clear"
    static let findReplaceCurrentButton = "AttoEditor.FindReplace.ReplaceCurrent"
    static let findReplaceAllButton = "AttoEditor.FindReplace.ReplaceAll"
    static let findCloseButton = "AttoEditor.FindReplace.Close"

    static let statusBar = "AttoEditor.StatusBar"
    static let statusBarLeftLabel = "AttoEditor.StatusBar.Left"
    static let statusBarLanguagePopUp = "AttoEditor.StatusBar.Language"
    static let statusBarLspLabel = "AttoEditor.StatusBar.LSP"
    static let statusBarPositionLabel = "AttoEditor.StatusBar.Position"
    static let statusBarSelectionLabel = "AttoEditor.StatusBar.Selection"
    static let statusBarFileSizeLabel = "AttoEditor.StatusBar.FileSize"

    static let sidebar = "AttoEditor.Sidebar"
    static let sidebarTabBar = "AttoEditor.Sidebar.TabBar"
    static let sidebarTabControl = "AttoEditor.Sidebar.TabControl"
    static let sidebarContentHost = "AttoEditor.Sidebar.ContentHost"

    static let fileExplorer = "AttoEditor.FileExplorer"
    static let fileExplorerHeader = "AttoEditor.FileExplorer.Header"
    static let fileExplorerOutline = "AttoEditor.FileExplorer.Outline"
    static let fileExplorerScrollView = "AttoEditor.FileExplorer.ScrollView"
    static let fileExplorerRow = "AttoEditor.FileExplorer.Row"
    static let fileExplorerRowTitle = "AttoEditor.FileExplorer.RowTitle"

    static let openedFiles = "AttoEditor.OpenedFiles"
    static let openedFilesHeader = "AttoEditor.OpenedFiles.Header"
    static let openedFilesTable = "AttoEditor.OpenedFiles.Table"
    static let openedFilesScrollView = "AttoEditor.OpenedFiles.ScrollView"
    static let openedFilesRow = "AttoEditor.OpenedFiles.Row"
    static let openedFilesRowTitle = "AttoEditor.OpenedFiles.RowTitle"

    static let findInFiles = "AttoEditor.FindInFiles"
    static let findInFilesHeader = "AttoEditor.FindInFiles.Header"
    static let findInFilesQueryField = "AttoEditor.FindInFiles.QueryField"
    static let findInFilesScopeControl = "AttoEditor.FindInFiles.Scope"
    static let findInFilesStatusLabel = "AttoEditor.FindInFiles.Status"
    static let findInFilesTable = "AttoEditor.FindInFiles.Table"
    static let findInFilesScrollView = "AttoEditor.FindInFiles.ScrollView"
    static let findInFilesRow = "AttoEditor.FindInFiles.Row"
    static let findInFilesRowTitle = "AttoEditor.FindInFiles.RowTitle"

    static let completionPanel = "AttoEditor.Completion.Panel"
    static let completionRoot = "AttoEditor.Completion.Root"
    static let completionTable = "AttoEditor.Completion.Table"
    static let completionScrollView = "AttoEditor.Completion.ScrollView"
    static let completionPreview = "AttoEditor.Completion.Preview"
    static let completionPreviewScrollView = "AttoEditor.Completion.PreviewScrollView"
    static let completionRow = "AttoEditor.Completion.Row"
    static let completionRowTitle = "AttoEditor.Completion.RowTitle"

    static func commandMenuItem(_ commandID: String) -> String {
        "AttoCommand.\(commandID)"
    }

    static func menu(_ title: String) -> String {
        "AttoMenu.\(title)"
    }

    static func commandPalettePanel(prefix: String) -> String {
        "\(prefix).Panel"
    }

    static func commandPaletteRoot(prefix: String) -> String {
        "\(prefix).Root"
    }

    static func commandPaletteSearchField(prefix: String) -> String {
        "\(prefix).SearchField"
    }

    static func commandPaletteTable(prefix: String) -> String {
        "\(prefix).Table"
    }

    static func commandPaletteScrollView(prefix: String) -> String {
        "\(prefix).ScrollView"
    }

    static func commandPaletteRow(prefix: String) -> String {
        "\(prefix).Row"
    }

    static func commandPaletteRowTitle(prefix: String) -> String {
        "\(prefix).RowTitle"
    }
}

