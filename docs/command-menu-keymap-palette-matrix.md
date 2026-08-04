# Command / Menu / Keymap / Palette Matrix

This matrix tracks the AttoEditor command surfaces that must stay aligned while
the app keeps adding Sublime-like behavior. It is intentionally organized by
command family rather than by source file so new commands have an obvious place
to document their product path and regression coverage.

## Sources Of Truth

- Command registry and command palette entries: `AttoAppDelegate.defaultCommands(orderForCommandPalette:)`.
- Native menu entries: `AttoMainMenuBuilder.build(appDelegate:)`.
- Default key bindings and user-keymap overlay: `AttoKeymap.defaultBindings` and `AttoKeymap.resolvedKeymap(...)`.
- Command execution and validation: `AttoAppDelegate.executeCommand(...)`, `validateMenuItem(_:)`, and `AttoCommandSchema`.

Every user-facing command should have a registry entry. Menu and keymap entries
must reference registry command IDs, and the command palette is the discoverable
fallback for commands that intentionally do not have a default shortcut.

## Matrix

| Command family | Command registry / palette | Menu path | Default keymap | App main path tests |
| --- | --- | --- | --- | --- |
| File and tabs (`file.*`) | Complete for new/open/save/reload/pin/close/bulk close/move/recent project. | `File` menu covers all current registry file commands. | Covers new/open/save/close/move; reload, pin, recent project, and bulk-close are palette/menu only. | `AttoEditorCoreDocumentCommandTests`, `AttoCoreWorkspaceCommandTests`, `AttoEditorKeymapCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`. |
| Edit, search, and text transforms (`editor.*`, `search.*`) | Complete for find/replace, formatting, line operations, indentation, snippets, comments, folding, and find-in-files. | `Edit`, `Selection`, and `View` menus expose the command groups that have native UI affordances. | Covers common editing/search/folding bindings; snippet placeholder and some structural commands are palette/menu only. | `AttoEditorCommandRegistryTests`, `AttoEditorCoreDocumentCommandTests`, `AttoAutoPairsAndBracketsTests`, `AttoEditorKeymapCommandTests`. |
| Cursor and selection (`cursor.*`, selection-oriented `editor.*`) | Cursor movement commands are generated from `CursorMovementCommand`; selection commands are explicit registry entries. | Selection commands are in `Selection`; cursor movement is keymap/palette-driven. | Cursor movement depends on resolved keymap/user overlay; common selection commands have defaults. | `AttoEditorCommandRegistryTests`, `AttoEditorKeymapCommandTests`, `AttoCoreWorkspaceCommandTests`. |
| View, panes, wrap, and minimap (`view.*`) | Complete for sidebar/minimap, split/focus/move/close pane, and wrap modes. | `View` menu, including the `Word Wrap` submenu. | Defaults exist for common sidebar/minimap/split/pane/wrap actions. | `AttoCoreWorkspaceCommandTests`, `AttoCoreWorkspaceDragProjectionTests`, `AttoEditorVisualLayoutTests`, `AttoEditorKeymapCommandTests`. |
| Workspace edit transactions (`workspace.*`) | Undo, redo, and history panel are registered and schema-gated by runtime feature availability. | `Edit` menu for undo/redo; history remains palette-driven. | Undo/redo have defaults; history is palette/menu discoverable through registry only. | `AttoEditorWorkspaceEditTransactionCommandTests`, `AttoEditorWorkspaceEditPreviewCommandTests`, `AttoEditorCommandRegistryTests/testCommandRegistryDisablesCommandsForMissingOptionalRuntimeFeatures`. |
| Go, quick open, and navigation (`go.*`) | Complete for quick open, line navigation, back/forward, and matching bracket. | `Go` menu. | Defaults for quick open, go to line, and matching bracket; back/forward are palette/menu only. | `AttoEditorCommandPaletteTests`, `AttoEditorLspNavigationCommandTests`, `AttoEditorKeymapCommandTests`. |
| LSP navigation and result panels (`lsp.go_to_*`, locations, symbols, problems, workbench) | Registered for requests, last-result panels, history, dock/workbench, pin/stale/refresh commands, and project/workspace result views. | `Go` menu. | Defaults exist for high-frequency document symbols, workspace symbols, completion, signature help, rename, and code actions; result workbench/history commands are palette/menu only. | `AttoEditorLspNavigationCommandTests`, `AttoEditorLspWorkbenchTests`, `AttoEditorLspWorkbenchCommandTests`, `AttoEditorLspWorkbenchOwnershipTests`, `AttoAccessibilityIdentifierTests`. |
| LSP derived-state actions (`code_lens`, `inlay_hints`, `document_links`, `document_colors`, `hierarchy`, diagnostics) | Registered for refresh/show/apply paths, with runtime feature requirements on interactive LSP commands. | `Go` and `View` menus expose the user-facing actions and panels. | Only the high-frequency LSP commands have defaults; refresh/show panel commands are palette/menu only. | `AttoEditorLspDerivedStateCommandTests`, `AttoEditorLspDiagnosticsCommandTests`, `AttoEditorLspWorkbenchRefreshTests`, `AttoEditorLspWorkbenchHierarchyCommandTests`. |
| Project LSP lifecycle/status (`lsp.*project*`, restart/shutdown) | Registered for project status, health, dashboard, log export/clear, and server restart/shutdown. | `Go` menu. | Palette/menu only by default to avoid accidental server lifecycle changes. | `AttoEditorProjectLspLifecycleCommandTests`, `AttoEditorProjectLspStatusCommandTests`, `AttoRuntimeCompatibilityTests`. |
| Settings and preferences (`settings.*`, `workbench.preferences`) | Registered for Preferences, opening user/workspace settings, and validation. | App menu. | Preferences has the standard default; settings open/validate are palette/menu only. | `AttoEditorSettingsCommandTests`, `AttoConfigurationSettingsTests`, `AttoConfigurationSettingsJSONLocationTests`, `AttoEditorKeymapCommandTests`. |
| Macros (`macro.*`) | Registered for recording, replay, named macro CRUD, delete history, import, and export; parameterized commands carry schemas. | `Tools` menu. | Defaults for toggle recording and replay last; named/history/import/export commands are palette/menu only. | `AttoEditorCommandMacroTests`, `AttoEditorCommandRegistryTests/testCommandRegistryCarriesParameterSchemasAndMacroPolicies`, `AttoEditorKeymapCommandTests`. |
| Sublime product boundaries (`build.*`, `package.*`, `panel.*`) | Registered as discoverable boundary commands with status feedback for unavailable build/package/plugin-panel APIs. | `Tools` menu. | No default keymap until a backing runtime is available. | `AttoEditorSublimeBoundaryCommandTests`, `AttoEditorCommandRegistryTests`, `AttoEditorKeymapCommandTests`. |

## Coverage Rules

- Add a command registry entry before adding a menu item or default key binding.
- Add menu coverage when a command is expected to be discoverable from the native menu bar.
- Add a default key binding only for commands that are frequent, low-risk, and consistent with platform conventions.
- Add parameter schema coverage for commands that can be invoked from keymap, palette recents, macros, or IPC with arguments.
- Add App main-path tests for every command that changes editor state, file/project state, LSP lifecycle, workspace edit transactions, or persistent configuration.

## Current Follow-Up Areas

- Sublime keymap compatibility covers comment/trailing-comma parsing, selector scope containment, context matching, conflict reporting, chord dispatch, argument routing, and malformed-file fallback.
- Snippets and macros have product paths; build systems, package resources, quick panels, input panels, and output panels expose explicit boundary feedback while backing runtime/plugin APIs remain future work.
- Commands without default key bindings are intentional only when the palette/menu path remains discoverable and tested.

## Verification

- `swift test --package-path swift --filter AttoEditorCommandTests/testCommandSurfacesReferenceRegisteredCommandIDs`
- `swift test --package-path swift --filter AttoEditorCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`
