import Foundation
import XCTest
@testable import EditorCoreFFI

final class ProcessingEditsTests: XCTestCase {
    func testApplyProcessingEditsSupportsClearOpsAndSingleObjectForm() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let state = try EditorState(library: library, initialText: "let value = 1\nsecond line\n", viewportWidth: 80)

        // Replace style layer => style appears in viewport blob
        try state.applyProcessingEditsJSON(#"{"op":"replace_style_layer","layer":777,"intervals":[{"start":0,"end":3,"style_id":99}]}"#)
        XCTAssertTrue(try state.viewportBlob(startVisualRow: 0, rowCount: 10).styleIds.contains(99))

        // Clear style layer (single object, not an array)
        try state.applyProcessingEditsJSON(#"{"op":"clear_style_layer","layer":777}"#)
        XCTAssertFalse(try state.viewportBlob(startVisualRow: 0, rowCount: 10).styleIds.contains(99))

        // Folding regions
        try state.applyProcessingEditsJSON(
            #"{"op":"replace_folding_regions","regions":[{"start_line":0,"end_line":1,"is_collapsed":true,"placeholder":"[...]"}],"preserve_collapsed":false}"#
        )
        var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
        XCTAssertGreaterThan(full.folding.regions.count, 0)

        try state.applyProcessingEditsJSON(#"{"op":"clear_folding_regions"}"#)
        full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
        XCTAssertEqual(full.folding.regions.count, 0)

        // Diagnostics
        try state.applyProcessingEditsJSON(
            #"{"op":"replace_diagnostics","diagnostics":[{"range":{"start":0,"end":1},"severity":"warning","message":"demo"}]}"#
        )
        var diagList = try JSONTestHelpers.object(try state.diagnosticsJSON())
        XCTAssertEqual(((diagList["diagnostics"] as? [Any]) ?? []).count, 1)

        try state.applyProcessingEditsJSON(#"{"op":"clear_diagnostics"}"#)
        diagList = try JSONTestHelpers.object(try state.diagnosticsJSON())
        XCTAssertEqual(((diagList["diagnostics"] as? [Any]) ?? []).count, 0)
        full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
        XCTAssertEqual(full.diagnostics.diagnosticsCount, 0)

        // Decorations (layered)
        try state.applyProcessingEditsJSON(
            #"{"op":"replace_decorations","layer":1,"decorations":[{"range":{"start":3,"end":3},"placement":"after","kind":{"kind":"inlay_hint"},"text":": i32","styles":[42]}]}"#
        )
        var decorations = try JSONTestHelpers.object(try state.decorationsJSON())
        XCTAssertGreaterThan(((decorations["layers"] as? [Any]) ?? []).count, 0)

        try state.applyProcessingEditsJSON(#"{"op":"clear_decorations","layer":1}"#)
        decorations = try JSONTestHelpers.object(try state.decorationsJSON())
        let layersAfterClear = (decorations["layers"] as? [Any]) ?? []
        XCTAssertEqual(layersAfterClear.count, 0)

        // Document symbols
        try state.applyProcessingEditsJSON(
            #"{"op":"replace_document_symbols","symbols":[{"name":"main","kind":{"kind":"function"},"range":{"start":0,"end":3},"selection_range":{"start":0,"end":3},"children":[]}]}"#
        )
        var symbols = try JSONTestHelpers.object(try state.documentSymbolsJSON())
        XCTAssertEqual(((symbols["symbols"] as? [Any]) ?? []).count, 1)

        try state.applyProcessingEditsJSON(#"{"op":"clear_document_symbols"}"#)
        symbols = try JSONTestHelpers.object(try state.documentSymbolsJSON())
        XCTAssertEqual(((symbols["symbols"] as? [Any]) ?? []).count, 0)
    }
}

