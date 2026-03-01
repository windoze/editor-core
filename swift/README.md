# EditorComponentKit (AppKit + TextKit)

`EditorComponentKit` is a Swift AppKit UI layer for `editor-core` and related capabilities (LSP/syntax/tree-sitter metadata via adapter APIs). It is transport-agnostic and can be wired to:

- direct Rust/C ABI calls (`editor-core-ffi`)
- IPC/service processes
- in-memory mock engines for tests/demo

## Features

- TextKit-based text rendering and input (`NSTextView`) with ligatures and emoji/grapheme-safe behavior.
- Styling pipeline (`styleID -> temporary attributes`) without mutating source text.
- Inlay text overlays (`before`, `after`, `aboveLine`) rendered non-destructively.
- Gutter with line numbers and fold markers.
- Indent guides + structure guides.
- Optional minimap with visible viewport highlight.
- Keybinding registry + command dispatching.
- Host extension points:
  - hover tooltips (`EditorHoverProvider`)
  - context menus (`EditorContextMenuProvider`)
  - custom command handling (`EditorCommand.custom`)

## Quick Start

```swift
import AppKit
import EditorComponentKit

let component = EditorComponentView(
    frame: NSRect(x: 0, y: 0, width: 900, height: 640),
    configuration: .init(
        features: .init(showsMinimap: true),
        visualStyle: .init(fontName: "SF Mono", fontSize: 14)
    )
)

let engine = MockEditorEngine(text: "fn main() {\\n    println!(\\\"hello\\\")\\n}\\n")
component.engine = engine
```

### Feature Flags

```swift
component.configuration.features = .init(
    showsGutter: true,
    showsLineNumbers: true,
    showsMinimap: true,
    showsIndentGuides: true,
    showsStructureGuides: true
)
```

### Configure Keybindings

```swift
component.bindKey(
    EditorKeyChord(key: "p", modifiers: [.command, .shift]),
    to: .custom(name: "showCommandPalette", payload: [:])
)

component.customCommandHandler = { name, payload in
    if name == "showCommandPalette" {
        // open host command palette
        return .success
    }
    return nil
}
```

### Hover and Context Menu Hooks

```swift
final class HoverProvider: EditorHoverProvider {
    func editorComponent(_ component: EditorComponentView, hoverAt position: EditorPosition) -> EditorHoverTooltip? {
        EditorHoverTooltip(title: "Symbol", message: "Line \\(position.line + 1)")
    }
}

final class MenuProvider: EditorContextMenuProvider {
    func editorComponent(
        _ component: EditorComponentView,
        contextMenuItemsAt position: EditorPosition
    ) -> [EditorContextMenuItem] {
        [
            EditorContextMenuItem(title: "Insert TODO", command: .insertText("// TODO")),
            .separator
        ]
    }
}
```

`hoverProvider` and `contextMenuProvider` are weak references; keep strong references in your host controller/window owner.

## Demo

Run the AppKit demo window:

```bash
cd swift
swift run EditorComponentDemo
```

## Test

```bash
cd swift
swift test
```

## Engine Adapter Contract

`EditorEngineProtocol` is the integration boundary. A production adapter can map these calls to `editor-core-ffi`:

- text + document/cursor state
- command execution
- style spans/inlays/folds/diagnostics
- viewport/minimap snapshots

This keeps AppKit rendering and host UX fully native while editor semantics stay in Rust.

## Production FFI Adapter

`EditorCoreFFIEngine` is included and calls `editor-core-ffi` directly through the C ABI:

```swift
import EditorComponentKit

let engine = try EditorCoreFFIEngine(
    initialText: "fn main() {}\\n",
    viewportWidth: 120
)
component.engine = engine
```

By default it tries to load the dynamic library from:

1. `EDITOR_CORE_FFI_DYLIB_PATH`
2. `EDITOR_CORE_REPO_ROOT/target/debug/<libeditor_core_ffi.*>`
3. `../target/debug/<libeditor_core_ffi.*>` relative to current working directory

You can also pass an explicit path via `libraryPath`.

### LSP / Sublime / Tree-sitter Bridges

- `EditorCoreFFILSPBridge`: URI and UTF-16 conversion helpers.
- `EditorCoreFFIEngine.applyLSP*` methods: convert LSP JSON payloads to processing edits and apply them.
- `EditorCoreFFISublimeProcessor`: apply Sublime syntax processing to the engine.
- `EditorCoreFFITreeSitterProcessor`: apply Tree-sitter processing to the engine.

### Build FFI Library

```bash
cargo build -p editor-core-ffi
```

## Current Implementation Status

- AppKit container + TextKit rendering/input: implemented.
- Styles, inlays, diagnostics rendering: implemented.
- Gutter (line numbers/folding), minimap, indent/structure guides: implemented.
- Custom keybindings, command dispatch, custom commands: implemented.
- Hover/context menu provider interfaces: implemented.
- Test suite and runnable demo target: implemented.
