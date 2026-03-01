#if canImport(AppKit)
import AppKit
import EditorComponentKit

@main
struct EditorComponentDemoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = DemoAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

private final class DemoAppDelegate: NSObject, NSApplicationDelegate, EditorComponentDelegate {
    private var window: NSWindow?
    private var component: EditorComponentView?
    private let hoverProvider = DemoHoverProvider()
    private let contextMenuProvider = DemoContextMenuProvider()
    private var demoEngine: EditorEngineProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification

        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EditorComponentDemo"
        window.isReleasedWhenClosed = false

        let palette = EditorStylePalette(styles: [
            1: .init(
                foreground: .init(red: 0.13, green: 0.32, blue: 0.86),
                bold: true
            ),
            2: .init(
                foreground: .init(red: 0.01, green: 0.49, blue: 0.22)
            ),
            3: .init(
                foreground: .init(red: 0.67, green: 0.09, blue: 0.38),
                italic: true
            ),
            4: .init(
                foreground: .init(red: 0.48, green: 0.25, blue: 0.79)
            ),
            5: .init(
                foreground: .init(red: 0.71, green: 0.07, blue: 0.07),
                underline: true
            )
        ])

        let configuration = EditorComponentConfiguration(
            features: .init(
                showsGutter: true,
                showsLineNumbers: true,
                showsMinimap: true,
                showsIndentGuides: true,
                showsStructureGuides: true
            ),
            visualStyle: .init(
                fontName: "SF Mono",
                fontSize: 14,
                lineHeightMultiplier: 1.3,
                enablesLigatures: true,
                stylePalette: palette,
                inlayFontScale: 0.88,
                inlayHorizontalPadding: 4,
                guideIndentColumns: 4
            )
        )

        let component = EditorComponentView(
            frame: window.contentView?.bounds ?? .zero,
            configuration: configuration
        )
        component.autoresizingMask = [.width, .height]
        component.delegate = self
        component.hoverProvider = hoverProvider
        component.contextMenuProvider = contextMenuProvider
        component.customCommandHandler = { name, _ in
            if name == "showCommandPalette" {
                NSSound.beep()
                return .success
            }
            return nil
        }
        component.bindKey(
            EditorKeyChord(key: "p", modifiers: [.command, .shift]),
            to: .custom(name: "showCommandPalette", payload: [:])
        )
        demoEngine = makeDemoEngine()
        component.engine = demoEngine

        window.contentView?.addSubview(component)
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.component = component
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return true
    }

    func editorComponent(_ component: EditorComponentView, didFail error: EditorCommandError) {
        _ = component
        NSLog("Editor error: %@", error.message)
    }

    func editorComponent(_ component: EditorComponentView, didExecute commandResult: EditorCommandResult) {
        _ = component
        _ = commandResult
    }

    private func makeDemoEngine() -> EditorEngineProtocol {
        let text = """
        func greet(name: String) -> String {
            let emoji = "👋"
            let message = "Hello, \\(name) \\(emoji)"
            return message
        }

        // Try: Cmd+Shift+P, right-click, hover for tooltips.
        """

        let styleSpans: [EditorStyleSpan] = [
            span(in: text, token: "func", styleID: 1),
            span(in: text, token: "let", styleID: 1),
            span(in: text, token: "return", styleID: 1),
            span(in: text, token: "\"👋\"", styleID: 2),
            span(in: text, token: "\"Hello, \\(name) \\(emoji)\"", styleID: 2),
            span(in: text, token: "// Try: Cmd+Shift+P, right-click, hover for tooltips.", styleID: 3)
        ]

        let foldRegions = [
            EditorFoldRegion(startLine: 0, endLine: 4, isCollapsed: false, placeholder: "{ ... }")
        ]

        let inlays = [
            EditorInlay(
                offset: scalarOffset(in: text, token: "name: String") + "name: String".unicodeScalars.count,
                text: " /* param */",
                placement: .after,
                styleIDs: [4]
            ),
            EditorInlay(
                offset: scalarOffset(in: text, token: "return"),
                text: "returns String",
                placement: .aboveLine,
                styleIDs: [4]
            )
        ]

        let diagnostics = EditorDiagnosticsSnapshot(items: [
            .init(
                startOffset: scalarOffset(in: text, token: "message"),
                endOffset: scalarOffset(in: text, token: "message") + "message".unicodeScalars.count,
                severity: "info",
                message: "Value propagated to return"
            )
        ])

        if let ffiEngine = try? EditorCoreFFIEngine(initialText: text, viewportWidth: 120) {
            let processingEditsJSON = """
            [
              {
                "op": "replace_style_layer",
                "layer": 131072,
                "intervals": [
                  { "start": \(styleSpans[0].startOffset), "end": \(styleSpans[0].endOffset), "style_id": \(styleSpans[0].styleID) },
                  { "start": \(styleSpans[1].startOffset), "end": \(styleSpans[1].endOffset), "style_id": \(styleSpans[1].styleID) },
                  { "start": \(styleSpans[2].startOffset), "end": \(styleSpans[2].endOffset), "style_id": \(styleSpans[2].styleID) },
                  { "start": \(styleSpans[3].startOffset), "end": \(styleSpans[3].endOffset), "style_id": \(styleSpans[3].styleID) },
                  { "start": \(styleSpans[4].startOffset), "end": \(styleSpans[4].endOffset), "style_id": \(styleSpans[4].styleID) },
                  { "start": \(styleSpans[5].startOffset), "end": \(styleSpans[5].endOffset), "style_id": \(styleSpans[5].styleID) }
                ]
              },
              {
                "op": "replace_folding_regions",
                "regions": [
                  {
                    "start_line": \(foldRegions[0].startLine),
                    "end_line": \(foldRegions[0].endLine),
                    "is_collapsed": \(foldRegions[0].isCollapsed ? "true" : "false"),
                    "placeholder": "\(foldRegions[0].placeholder)"
                  }
                ],
                "preserve_collapsed": false
              },
              {
                "op": "replace_decorations",
                "layer": 1,
                "decorations": [
                  {
                    "range": { "start": \(inlays[0].offset), "end": \(inlays[0].offset) },
                    "placement": "after",
                    "kind": { "kind": "inlay_hint" },
                    "text": "\(inlays[0].text)",
                    "styles": \(inlays[0].styleIDs)
                  },
                  {
                    "range": { "start": \(inlays[1].offset), "end": \(inlays[1].offset) },
                    "placement": "above_line",
                    "kind": { "kind": "code_lens" },
                    "text": "\(inlays[1].text)",
                    "styles": \(inlays[1].styleIDs)
                  }
                ]
              },
              {
                "op": "replace_diagnostics",
                "diagnostics": [
                  {
                    "range": { "start": \(diagnostics.items[0].startOffset), "end": \(diagnostics.items[0].endOffset) },
                    "severity": "\(diagnostics.items[0].severity)",
                    "message": "\(diagnostics.items[0].message)"
                  }
                ]
              }
            ]
            """
            try? ffiEngine.applyProcessingEditsJSON(processingEditsJSON)
            return ffiEngine
        }

        return MockEditorEngine(
            text: text,
            styleSpanData: styleSpans,
            inlayData: inlays,
            foldRegionData: foldRegions,
            diagnosticsData: diagnostics
        )
    }
}

private final class DemoHoverProvider: EditorHoverProvider {
    func editorComponent(_ component: EditorComponentView, hoverAt position: EditorPosition) -> EditorHoverTooltip? {
        _ = component
        return EditorHoverTooltip(
            title: "Symbol",
            message: "Line \(position.line + 1), Column \(position.column + 1)"
        )
    }
}

private final class DemoContextMenuProvider: EditorContextMenuProvider {
    func editorComponent(
        _ component: EditorComponentView,
        contextMenuItemsAt position: EditorPosition
    ) -> [EditorContextMenuItem] {
        [
            EditorContextMenuItem(
                title: "Insert Log Line",
                command: .insertText("print(\"line \(position.line + 1)\")")
            ),
            .separator,
            EditorContextMenuItem(title: "Fold This Block") {
                component.toggleFold(startLine: position.line)
            }
        ]
    }
}

private func scalarOffset(in text: String, token: String) -> Int {
    guard let range = text.range(of: token) else {
        return 0
    }
    return text[..<range.lowerBound].unicodeScalars.count
}

private func span(in text: String, token: String, styleID: UInt32) -> EditorStyleSpan {
    let start = scalarOffset(in: text, token: token)
    let end = start + token.unicodeScalars.count
    return EditorStyleSpan(startOffset: start, endOffset: end, styleID: styleID)
}
#else
@main
struct EditorComponentDemoMain {
    static func main() {
        print("EditorComponentDemo requires AppKit/macOS.")
    }
}
#endif
