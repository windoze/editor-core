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

    static let lspLocationPanel = "AttoEditor.LSP.LocationPanel.Panel"
    static let lspLocationPanelRoot = "AttoEditor.LSP.LocationPanel.Root"
    static let lspLocationPanelSearchField = "AttoEditor.LSP.LocationPanel.SearchField"
    static let lspLocationPanelMetadataLabel = "AttoEditor.LSP.LocationPanel.Metadata"
    static let lspLocationPanelTable = "AttoEditor.LSP.LocationPanel.Table"
    static let lspLocationPanelScrollView = "AttoEditor.LSP.LocationPanel.ScrollView"
    static let lspLocationPanelRow = "AttoEditor.LSP.LocationPanel.Row"
    static let lspLocationPanelRowTitle = "AttoEditor.LSP.LocationPanel.RowTitle"

    static let lspSymbolPanel = "AttoEditor.LSP.SymbolPanel.Panel"
    static let lspSymbolPanelRoot = "AttoEditor.LSP.SymbolPanel.Root"
    static let lspSymbolPanelSearchField = "AttoEditor.LSP.SymbolPanel.SearchField"
    static let lspSymbolPanelMetadataLabel = "AttoEditor.LSP.SymbolPanel.Metadata"
    static let lspSymbolPanelTable = "AttoEditor.LSP.SymbolPanel.Table"
    static let lspSymbolPanelScrollView = "AttoEditor.LSP.SymbolPanel.ScrollView"
    static let lspSymbolPanelRow = "AttoEditor.LSP.SymbolPanel.Row"
    static let lspSymbolPanelRowTitle = "AttoEditor.LSP.SymbolPanel.RowTitle"

    static let problemsPanel = "AttoEditor.LSP.ProblemsPanel.Panel"
    static let problemsPanelRoot = "AttoEditor.LSP.ProblemsPanel.Root"
    static let problemsPanelSearchField = "AttoEditor.LSP.ProblemsPanel.SearchField"
    static let problemsPanelTable = "AttoEditor.LSP.ProblemsPanel.Table"
    static let problemsPanelScrollView = "AttoEditor.LSP.ProblemsPanel.ScrollView"
    static let problemsPanelRow = "AttoEditor.LSP.ProblemsPanel.Row"
    static let problemsPanelRowTitle = "AttoEditor.LSP.ProblemsPanel.RowTitle"

    static let workspaceProblemsPanel = "AttoEditor.LSP.WorkspaceProblemsPanel.Panel"
    static let workspaceProblemsPanelRoot = "AttoEditor.LSP.WorkspaceProblemsPanel.Root"
    static let workspaceProblemsPanelSearchField = "AttoEditor.LSP.WorkspaceProblemsPanel.SearchField"
    static let workspaceProblemsPanelTable = "AttoEditor.LSP.WorkspaceProblemsPanel.Table"
    static let workspaceProblemsPanelScrollView = "AttoEditor.LSP.WorkspaceProblemsPanel.ScrollView"
    static let workspaceProblemsPanelRow = "AttoEditor.LSP.WorkspaceProblemsPanel.Row"
    static let workspaceProblemsPanelRowTitle = "AttoEditor.LSP.WorkspaceProblemsPanel.RowTitle"

    static let codeLensPanel = "AttoEditor.LSP.CodeLensPanel.Panel"
    static let codeLensPanelRoot = "AttoEditor.LSP.CodeLensPanel.Root"
    static let codeLensPanelSearchField = "AttoEditor.LSP.CodeLensPanel.SearchField"
    static let codeLensPanelMetadataLabel = "AttoEditor.LSP.CodeLensPanel.Metadata"
    static let codeLensPanelTable = "AttoEditor.LSP.CodeLensPanel.Table"
    static let codeLensPanelScrollView = "AttoEditor.LSP.CodeLensPanel.ScrollView"
    static let codeLensPanelRow = "AttoEditor.LSP.CodeLensPanel.Row"
    static let codeLensPanelRowTitle = "AttoEditor.LSP.CodeLensPanel.RowTitle"

    static let inlayHintPanel = "AttoEditor.LSP.InlayHintPanel.Panel"
    static let inlayHintPanelRoot = "AttoEditor.LSP.InlayHintPanel.Root"
    static let inlayHintPanelSearchField = "AttoEditor.LSP.InlayHintPanel.SearchField"
    static let inlayHintPanelMetadataLabel = "AttoEditor.LSP.InlayHintPanel.Metadata"
    static let inlayHintPanelTable = "AttoEditor.LSP.InlayHintPanel.Table"
    static let inlayHintPanelScrollView = "AttoEditor.LSP.InlayHintPanel.ScrollView"
    static let inlayHintPanelRow = "AttoEditor.LSP.InlayHintPanel.Row"
    static let inlayHintPanelRowTitle = "AttoEditor.LSP.InlayHintPanel.RowTitle"

    static let documentLinkPanel = "AttoEditor.LSP.DocumentLinkPanel.Panel"
    static let documentLinkPanelRoot = "AttoEditor.LSP.DocumentLinkPanel.Root"
    static let documentLinkPanelSearchField = "AttoEditor.LSP.DocumentLinkPanel.SearchField"
    static let documentLinkPanelMetadataLabel = "AttoEditor.LSP.DocumentLinkPanel.Metadata"
    static let documentLinkPanelTable = "AttoEditor.LSP.DocumentLinkPanel.Table"
    static let documentLinkPanelScrollView = "AttoEditor.LSP.DocumentLinkPanel.ScrollView"
    static let documentLinkPanelRow = "AttoEditor.LSP.DocumentLinkPanel.Row"
    static let documentLinkPanelRowTitle = "AttoEditor.LSP.DocumentLinkPanel.RowTitle"

    static let documentColorPanel = "AttoEditor.LSP.DocumentColorPanel.Panel"
    static let documentColorPanelRoot = "AttoEditor.LSP.DocumentColorPanel.Root"
    static let documentColorPanelSearchField = "AttoEditor.LSP.DocumentColorPanel.SearchField"
    static let documentColorPanelMetadataLabel = "AttoEditor.LSP.DocumentColorPanel.Metadata"
    static let documentColorPanelTable = "AttoEditor.LSP.DocumentColorPanel.Table"
    static let documentColorPanelScrollView = "AttoEditor.LSP.DocumentColorPanel.ScrollView"
    static let documentColorPanelRow = "AttoEditor.LSP.DocumentColorPanel.Row"
    static let documentColorPanelSwatch = "AttoEditor.LSP.DocumentColorPanel.Swatch"
    static let documentColorPanelRowTitle = "AttoEditor.LSP.DocumentColorPanel.RowTitle"

    static let hierarchyPanel = "AttoEditor.LSP.HierarchyPanel.Panel"
    static let hierarchyPanelRoot = "AttoEditor.LSP.HierarchyPanel.Root"
    static let hierarchyPanelSearchField = "AttoEditor.LSP.HierarchyPanel.SearchField"
    static let hierarchyPanelMetadataLabel = "AttoEditor.LSP.HierarchyPanel.Metadata"
    static let hierarchyPanelTable = "AttoEditor.LSP.HierarchyPanel.Table"
    static let hierarchyPanelScrollView = "AttoEditor.LSP.HierarchyPanel.ScrollView"
    static let hierarchyPanelRow = "AttoEditor.LSP.HierarchyPanel.Row"
    static let hierarchyPanelRowTitle = "AttoEditor.LSP.HierarchyPanel.RowTitle"

    static let workspaceEditPreviewPanel = "AttoEditor.WorkspaceEditPreview.Panel"
    static let workspaceEditPreviewRoot = "AttoEditor.WorkspaceEditPreview.Root"
    static let workspaceEditPreviewSummary = "AttoEditor.WorkspaceEditPreview.Summary"
    static let workspaceEditPreviewTable = "AttoEditor.WorkspaceEditPreview.Table"
    static let workspaceEditPreviewTableScrollView = "AttoEditor.WorkspaceEditPreview.TableScrollView"
    static let workspaceEditPreviewRow = "AttoEditor.WorkspaceEditPreview.Row"
    static let workspaceEditPreviewRowTitle = "AttoEditor.WorkspaceEditPreview.RowTitle"
    static let workspaceEditPreviewDetail = "AttoEditor.WorkspaceEditPreview.Detail"
    static let workspaceEditPreviewDetailScrollView = "AttoEditor.WorkspaceEditPreview.DetailScrollView"
    static let workspaceEditPreviewApplyButton = "AttoEditor.WorkspaceEditPreview.Apply"
    static let workspaceEditPreviewCancelButton = "AttoEditor.WorkspaceEditPreview.Cancel"

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
