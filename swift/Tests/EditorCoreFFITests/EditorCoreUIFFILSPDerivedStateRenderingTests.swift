import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testDerivedStateSnapshotsExposeLspAndFoldingState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {\n  value\n}\n", viewportWidthCells: 80)

        let diagnosticsParams = """
        {
          "uri": "file:///test.rs",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 2 },
                "end": { "line": 1, "character": 7 }
              },
              "severity": 2,
              "code": "unused",
              "source": "unit-test",
              "message": "value is unused"
            }
          ],
          "version": 1
        }
        """
        try ui.lspApplyDiagnosticsJSON(diagnosticsParams)

        let diagnostics = try JSONTestHelpers.object(try ui.diagnosticsJSON())
        let diagnosticList = try XCTUnwrap(diagnostics["diagnostics"] as? [[String: Any]])
        XCTAssertEqual(diagnosticList.count, 1)
        XCTAssertEqual(diagnosticList[0]["message"] as? String, "value is unused")
        XCTAssertEqual(diagnosticList[0]["severity"] as? String, "warning")
        let diagnosticsSnapshot = try ui.diagnosticsSnapshot()
        XCTAssertEqual(diagnosticsSnapshot.diagnostics.count, 1)
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].message, "value is unused")
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].code, "unused")
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].source, "unit-test")

        let inlayHints = """
        [
          {
            "position": { "line": 1, "character": 7 },
            "label": ": i32",
            "tooltip": "inferred type"
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(inlayHints)

        let decorations = try JSONTestHelpers.object(try ui.decorationsJSON())
        let decorationLayers = try XCTUnwrap(decorations["layers"] as? [[String: Any]])
        let inlayLayer = try XCTUnwrap(decorationLayers.first { ($0["layer"] as? Int) == 1 })
        let inlayDecorations = try XCTUnwrap(inlayLayer["decorations"] as? [[String: Any]])
        XCTAssertEqual(inlayDecorations.first?["text"] as? String, ": i32")
        let inlayKind = try XCTUnwrap(inlayDecorations.first?["kind"] as? [String: Any])
        XCTAssertEqual(inlayKind["kind"] as? String, "inlay_hint")
        let decorationsSnapshot = try ui.decorationsSnapshot()
        let typedInlayLayer = try XCTUnwrap(decorationsSnapshot.layers.first { $0.layer == 1 })
        let typedInlay = try XCTUnwrap(typedInlayLayer.decorations.first)
        XCTAssertEqual(typedInlay.text, ": i32")
        XCTAssertEqual(typedInlay.kind, .object(["kind": .string("inlay_hint")]))

        let documentSymbols = """
        [
          {
            "name": "main",
            "detail": "fn()",
            "kind": 12,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 3 },
              "end": { "line": 0, "character": 7 }
            },
            "children": []
          }
        ]
        """
        try ui.lspApplyDocumentSymbolsJSON(documentSymbols)

        let symbols = try JSONTestHelpers.object(try ui.documentSymbolsJSON())
        let symbolList = try XCTUnwrap(symbols["symbols"] as? [[String: Any]])
        XCTAssertEqual(symbolList.first?["name"] as? String, "main")
        let symbolKind = try XCTUnwrap(symbolList.first?["kind"] as? [String: Any])
        XCTAssertEqual(symbolKind["kind"] as? String, "function")
        let symbolsSnapshot = try ui.documentSymbolsSnapshot()
        let typedSymbol = try XCTUnwrap(symbolsSnapshot.symbols.first)
        XCTAssertEqual(typedSymbol.name, "main")
        XCTAssertEqual(typedSymbol.detail, "fn()")
        XCTAssertEqual(typedSymbol.kind, .object(["kind": .string("function")]))

        try ui.lspApplySemanticTokens([0, 3, 4, 7, 0])

        let styleIntervals = try JSONTestHelpers.object(try ui.styleIntervalsJSON(start: 0, end: 24))
        let styleLayers = try XCTUnwrap(styleIntervals["layers"] as? [[String: Any]])
        let semanticLayer = try XCTUnwrap(styleLayers.first { ($0["layer"] as? Int) == 1 })
        let semanticIntervals = try XCTUnwrap(semanticLayer["intervals"] as? [[String: Any]])
        XCTAssertEqual(semanticIntervals.first?["start"] as? Int, 3)
        XCTAssertEqual(semanticIntervals.first?["end"] as? Int, 7)
        XCTAssertEqual(semanticIntervals.first?["style_id"] as? Int, 0x0007_0000)
        let styleSnapshot = try ui.styleIntervalsSnapshot(start: 0, end: 24)
        let typedSemanticLayer = try XCTUnwrap(styleSnapshot.layers.first { $0.layer == 1 })
        let typedSemanticInterval = try XCTUnwrap(typedSemanticLayer.intervals.first)
        XCTAssertEqual(typedSemanticInterval.start, 3)
        XCTAssertEqual(typedSemanticInterval.end, 7)
        XCTAssertEqual(typedSemanticInterval.styleId, 0x0007_0000)

        let foldingRanges = """
        [
          {
            "startLine": 0,
            "endLine": 2,
            "kind": "region"
          }
        ]
        """
        try ui.lspApplyFoldingRangesJSON(foldingRanges)

        let lspFolding = try JSONTestHelpers.object(try ui.foldingRegionsJSON())
        let lspRegions = try XCTUnwrap(lspFolding["regions"] as? [[String: Any]])
        XCTAssertTrue(lspRegions.contains {
            ($0["start_line"] as? Int) == 0
                && ($0["end_line"] as? Int) == 2
                && ($0["is_collapsed"] as? Bool) == false
        })
        let lspFoldingSnapshot = try ui.foldingRegionsSnapshot()
        XCTAssertTrue(lspFoldingSnapshot.regions.contains {
            $0.startLine == 0 && $0.endLine == 2 && $0.isCollapsed == false
        })

        try ui.fold(startLine: 0, endLine: 2)

        let folding = try JSONTestHelpers.object(try ui.foldingRegionsJSON())
        let regions = try XCTUnwrap(folding["regions"] as? [[String: Any]])
        XCTAssertTrue(regions.contains {
            ($0["start_line"] as? Int) == 0
                && ($0["end_line"] as? Int) == 2
                && ($0["is_collapsed"] as? Bool) == true
        })
        let foldingSnapshot = try ui.foldingRegionsSnapshot()
        XCTAssertTrue(foldingSnapshot.regions.contains {
            $0.startLine == 0 && $0.endLine == 2 && $0.isCollapsed == true
        })
    }

    func testLspSemanticTokensAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // encode_semantic_style_id(token_type=7, token_modifiers=0) => 0x0007_0000
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0007_0000, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        // Highlight cell at col=1 (line 0, utf16 start=1, len=1).
        try ui.lspApplySemanticTokens([0, 1, 1, 7, 0])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspInlayHintsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the inlay hint label so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP inlay hint virtual text: 0x0800_0001
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0001, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "position": { "line": 0, "character": 1 },
            "label": " "
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Inlay hint is inserted at offset=1 => between 'a' and 'b' => col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspInlayHintsAffectHitTestingAndCaretPoint() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        let result = """
        [
          {
            "position": { "line": 0, "character": 1 },
            "label": " "
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(result)

        // With the inlay hint inserted between 'a' and 'b', the 'b' cell shifts right by 1.
        // So x=25 should hit 'b' (offset=1) instead of end-of-line (offset=2).
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 25, yPx: 10), 1)

        let pt = try ui.charOffsetToViewPoint(offset: 2)
        XCTAssertEqual(pt.xPx, 30)
        XCTAssertEqual(pt.yPx, 0)
        XCTAssertEqual(pt.lineHeightPx, 20)
    }

    func testLspCodeLensAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the code lens title so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "line1\nline2\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP code lens virtual text: 0x0800_0002
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0002, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": " ", "command": "noop" }
          }
        ]
        """
        try ui.lspApplyCodeLensJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Code lens is an above-line virtual line inserted at the very top => row=0, col=0.
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [1, 200, 2, 255])
    }

    func testCodeLensHitTestReturnsPayloadJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "line1\nline2\n", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 400, heightPx: 80, scale: 1)

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": "Run tests", "command": "test.run", "arguments": [1] }
          }
        ]
        """
        try ui.lspApplyCodeLensJSON(result)

        let json = try ui.codeLensJSONAtViewPoint(xPx: 5, yPx: 10)
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains(#""title":"Run tests""#) == true)
        XCTAssertTrue(json?.contains(#""command":"test.run""#) == true)

        XCTAssertNil(try ui.codeLensJSONAtViewPoint(xPx: 200, yPx: 10))
        XCTAssertNil(try ui.codeLensJSONAtViewPoint(xPx: 5, yPx: 30))
    }

    func testLspDocumentLinksAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the link range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 20, scale: 1)

        // Built-in style id for LSP document links underline: 0x0800_0003
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0003, foreground: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "target": "https://example.com"
          }
        ]
        """
        try ui.lspApplyDocumentLinksJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Underline is drawn at y = line_height_px - 1 (scale=1), i.e. y=9.
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 9), [1, 200, 2, 255])
    }

    func testDocumentLinkHitTestReturnsPayloadJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 20, scale: 1)

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "target": "https://example.com"
          }
        ]
        """
        try ui.lspApplyDocumentLinksJSON(result)

        let p = try ui.charOffsetToViewPoint(offset: 1)
        let json = try ui.documentLinkJSONAtViewPoint(xPx: p.xPx + 1, yPx: p.yPx + 1)
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("https://example.com") == true)

        let none = try ui.documentLinkJSONAtViewPoint(xPx: 1, yPx: 1)
        XCTAssertNil(none)
    }

    func testLspDocumentHighlightsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP document highlight text: 0x0400_0001
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0400_0001, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "kind": 1
          }
        ]
        """
        try ui.lspApplyDocumentHighlightsJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Highlighted cell at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }
}
