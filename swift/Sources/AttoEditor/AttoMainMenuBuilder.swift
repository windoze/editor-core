import AppKit
import Foundation

@MainActor
enum AttoMainMenuBuilder {
    static func build(appDelegate: AttoAppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("App"))
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About AttoEditor", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(commandItem(title: "Preferences...", commandID: "workbench.preferences", appDelegate: appDelegate))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AttoEditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        fileMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("File"))
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(commandItem(title: "New File", commandID: "file.new", appDelegate: appDelegate))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(title: "Open Folder...", commandID: "file.open_folder", appDelegate: appDelegate))
        fileMenu.addItem(commandItem(title: "Open File...", commandID: "file.open_file", appDelegate: appDelegate))
        fileMenu.addItem(commandItem(title: "Save", commandID: "file.save", appDelegate: appDelegate))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(title: "Close Tab", commandID: "file.close_tab", appDelegate: appDelegate))
        fileMenu.addItem(commandItem(title: "Move Tab Left", commandID: "file.move_tab_left", appDelegate: appDelegate))
        fileMenu.addItem(commandItem(title: "Move Tab Right", commandID: "file.move_tab_right", appDelegate: appDelegate))

        let editMenuItem = NSMenuItem()
        editMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("Edit"))
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(commandItem(title: "Find...", commandID: "editor.find", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Replace...", commandID: "editor.replace", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Find in Files...", commandID: "search.find_in_files", appDelegate: appDelegate))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(title: "Format Document", commandID: "editor.format_document", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Format Selection", commandID: "editor.format_selection", appDelegate: appDelegate))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(title: "Duplicate Line", commandID: "editor.duplicate_lines", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Delete Line", commandID: "editor.delete_lines", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Move Line Up", commandID: "editor.move_lines_up", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Move Line Down", commandID: "editor.move_lines_down", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Join Lines", commandID: "editor.join_lines", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Split Line", commandID: "editor.split_line", appDelegate: appDelegate))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(title: "Indent", commandID: "editor.indent", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Outdent", commandID: "editor.outdent", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Delete to Previous Tab Stop", commandID: "editor.delete_to_prev_tab_stop", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Apply Snippet...", commandID: "editor.apply_snippet", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Snippet Next Placeholder", commandID: "editor.snippet_next_placeholder", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Snippet Previous Placeholder", commandID: "editor.snippet_prev_placeholder", appDelegate: appDelegate))
        editMenu.addItem(commandItem(title: "Toggle Line Comment", commandID: "editor.toggle_line_comment", appDelegate: appDelegate))

        let selectionMenuItem = NSMenuItem()
        selectionMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("Selection"))
        mainMenu.addItem(selectionMenuItem)
        let selectionMenu = NSMenu(title: "Selection")
        selectionMenuItem.submenu = selectionMenu
        selectionMenu.addItem(commandItem(title: "Select Word", commandID: "editor.select_word", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Select Line", commandID: "editor.select_line", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Expand Selection", commandID: "editor.expand_selection", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Expand Selection with LSP", commandID: "lsp.selection_range", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Linked Editing with LSP", commandID: "lsp.linked_editing", appDelegate: appDelegate))
        selectionMenu.addItem(.separator())
        selectionMenu.addItem(commandItem(title: "Add Cursor Above", commandID: "editor.add_cursor_above", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Add Cursor Below", commandID: "editor.add_cursor_below", appDelegate: appDelegate))
        selectionMenu.addItem(.separator())
        selectionMenu.addItem(commandItem(title: "Add Next Occurrence", commandID: "editor.add_next_occurrence", appDelegate: appDelegate))
        selectionMenu.addItem(commandItem(title: "Add All Occurrences", commandID: "editor.add_all_occurrences", appDelegate: appDelegate))

        let viewMenuItem = NSMenuItem()
        viewMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("View"))
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(commandItem(title: "Toggle Sidebar", commandID: "view.toggle_sidebar", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Toggle Minimap", commandID: "view.toggle_minimap", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Split Right", commandID: "view.split_right", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Focus Next Pane", commandID: "view.focus_next_pane", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Focus Previous Pane", commandID: "view.focus_previous_pane", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Move Pane Left", commandID: "view.move_pane_left", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Move Pane Right", commandID: "view.move_pane_right", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Close Pane", commandID: "view.close_pane", appDelegate: appDelegate))
        viewMenu.addItem(.separator())
        let wrapMenuItem = NSMenuItem(title: "Word Wrap", action: nil, keyEquivalent: "")
        wrapMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("WordWrap"))
        let wrapMenu = NSMenu(title: "Word Wrap")
        wrapMenu.addItem(commandItem(title: "Off", commandID: "view.wrap.none", appDelegate: appDelegate))
        wrapMenu.addItem(commandItem(title: "By Character", commandID: "view.wrap.char", appDelegate: appDelegate))
        wrapMenu.addItem(commandItem(title: "By Word", commandID: "view.wrap.word", appDelegate: appDelegate))
        wrapMenuItem.submenu = wrapMenu
        viewMenu.addItem(wrapMenuItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(title: "Fold Selection", commandID: "editor.fold_selection", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Refresh Folding Ranges", commandID: "lsp.refresh_folding_ranges", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Unfold at Cursor", commandID: "editor.unfold", appDelegate: appDelegate))
        viewMenu.addItem(commandItem(title: "Unfold All", commandID: "editor.unfold_all", appDelegate: appDelegate))

        let goMenuItem = NSMenuItem()
        goMenuItem.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.menu("Go"))
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu
        goMenu.addItem(commandItem(title: "Go to File...", commandID: "go.file", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Go to Line...", commandID: "go.line", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Command Palette...", commandID: "workbench.command_palette", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Problems...", commandID: "lsp.problems", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Problems Panel", commandID: "lsp.show_problems_panel", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Document Symbols...", commandID: "lsp.document_symbols", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Workspace Symbols...", commandID: "lsp.workspace_symbols", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Last Symbols...", commandID: "lsp.show_last_symbols", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Symbol History...", commandID: "lsp.show_symbol_history", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Symbols Panel", commandID: "lsp.show_symbols_panel", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Document Colors...", commandID: "lsp.document_colors", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Pick Document Color...", commandID: "lsp.pick_document_color", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Completion", commandID: "lsp.completion", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Signature Help", commandID: "lsp.signature_help", appDelegate: appDelegate))
        goMenu.addItem(.separator())
        goMenu.addItem(commandItem(title: "Back", commandID: "go.back", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Forward", commandID: "go.forward", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Go to Matching Bracket", commandID: "go.matching_bracket", appDelegate: appDelegate))
        goMenu.addItem(.separator())
        goMenu.addItem(commandItem(title: "Go to Definition", commandID: "lsp.go_to_definition", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Go to Declaration", commandID: "lsp.go_to_declaration", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Go to Type Definition", commandID: "lsp.go_to_type_definition", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Go to Implementation", commandID: "lsp.go_to_implementation", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Find References", commandID: "lsp.find_references", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Last Locations...", commandID: "lsp.show_last_locations", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Location History...", commandID: "lsp.show_location_history", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Show Locations Panel", commandID: "lsp.show_locations_panel", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Incoming Calls", commandID: "lsp.call_hierarchy_incoming", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Outgoing Calls", commandID: "lsp.call_hierarchy_outgoing", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Supertypes", commandID: "lsp.type_hierarchy_supertypes", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Subtypes", commandID: "lsp.type_hierarchy_subtypes", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Rename Symbol", commandID: "lsp.rename", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Code Actions", commandID: "lsp.code_actions", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Code Lens Actions", commandID: "lsp.code_lens_actions", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Code Lens at Cursor", commandID: "lsp.code_lens_at_cursor", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Refresh Code Lens", commandID: "lsp.refresh_code_lens", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Quick Fixes", commandID: "lsp.quick_fix", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Refactor Actions", commandID: "lsp.refactor", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Source Actions", commandID: "lsp.source_actions", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Organize Imports", commandID: "lsp.organize_imports", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Fix All", commandID: "lsp.fix_all", appDelegate: appDelegate))
        goMenu.addItem(commandItem(title: "Workspace Diagnostics", commandID: "lsp.workspace_diagnostics", appDelegate: appDelegate))

        return mainMenu
    }

    private static func commandItem(title: String, commandID: String, appDelegate: AttoAppDelegate) -> NSMenuItem {
        let binding = appDelegate.keyBinding(forCommandID: commandID)
        let item = NSMenuItem(
            title: title,
            action: #selector(AttoAppDelegate.commandMenuItemClicked(_:)),
            keyEquivalent: binding?.keyEquivalent ?? ""
        )
        item.keyEquivalentModifierMask = binding?.modifiers ?? []
        item.target = appDelegate
        item.representedObject = commandID
        item.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.commandMenuItem(commandID))
        return item
    }
}
