import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testEditorUILSPResultEventsWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertEqual(try ui.lspResultEventsLatestSequence(), 0)
        let events = try ui.lspResultEvents()
        XCTAssertEqual(events.latestSequence, 0)
        XCTAssertTrue(events.events.isEmpty)

        XCTAssertEqual(try ui.lspRequestEventsLatestSequence(), 0)
        let requestEvents = try ui.lspRequestEvents()
        XCTAssertEqual(requestEvents.latestSequence, 0)
        XCTAssertTrue(requestEvents.events.isEmpty)
        XCTAssertFalse(try ui.lspCancelRequest(999))
        XCTAssertFalse(try ui.lspMarkRequestTimedOut(999))
        XCTAssertThrowsError(
            try ui.lspDidChangeWorkspaceFolders(
                added: [.init(uri: "file:///tmp/added", name: "added")],
                removed: []
            )
        )
        XCTAssertThrowsError(
            try ui.lspDidOpenDocument(
                uri: "file:///tmp/opened.rs",
                languageId: "rust",
                text: "fn opened() {}\n"
            )
        )
        XCTAssertThrowsError(try ui.lspDidChangeDocument(uri: "file:///tmp/opened.rs", text: "changed"))
        XCTAssertThrowsError(try ui.lspDidSaveDocument(uri: "file:///tmp/saved.rs", text: "saved"))
        XCTAssertThrowsError(try ui.lspDidCloseDocument(uri: "file:///tmp/saved.rs"))
        XCTAssertEqual(try ui.lspRequestEventsLatestSequence(), 0)

        XCTAssertEqual(try ui.stateEventsLatestSequence(), 0)
        let stateEvents = try ui.stateEvents()
        XCTAssertEqual(stateEvents.latestSequence, 0)
        XCTAssertTrue(stateEvents.events.isEmpty)
        XCTAssertFalse(try ui.lspShutdown())
        XCTAssertFalse(try ui.lspIsEnabled())
    }

    func testEditorUIStateEventsRecordTextAndDirtyChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

        try ui.insertText("x")
        var snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 3)
        XCTAssertEqual(snapshot.events.map(\.kind), ["dirty_changed", "selection_changed", "text_changed"])
        XCTAssertEqual(snapshot.events[0].kindValue, .dirtyChanged)
        XCTAssertEqual(snapshot.events[0].familyKind, .document)
        XCTAssertEqual(snapshot.events[0].dirty?.isModified, true)
        XCTAssertEqual(snapshot.events[1].kindValue, .selectionChanged)
        XCTAssertEqual(snapshot.events[1].familyKind, .document)
        XCTAssertEqual(snapshot.events[1].selection?.primary.offset, 1)
        XCTAssertEqual(snapshot.events[1].selection?.selectionCount, 1)
        XCTAssertEqual(snapshot.events[1].selection?.hasSelection, false)
        XCTAssertEqual(snapshot.events[2].kindValue, .textChanged)
        XCTAssertEqual(snapshot.events[2].text?.textVersion, 1)
        XCTAssertEqual(snapshot.events[2].text?.charLen, 1)
        XCTAssertEqual(snapshot.events[2].text?.isModified, true)
        XCTAssertNil(snapshot.events[2].dirty)
        XCTAssertNil(snapshot.events[2].selection)

        try ui.markSaved()
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 4)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .dirtyChanged)
        XCTAssertEqual(snapshot.events[0].dirty?.isModified, false)
    }

    func testEditorUIStateEventsRecordSelectionChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abcd", viewportWidthCells: 80)

        try ui.setSelections(
            [
                EcuSelectionRange(start: 1, end: 3),
                EcuSelectionRange(start: 4, end: 4),
            ],
            primaryIndex: 0
        )

        let snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        let event = try XCTUnwrap(snapshot.events.first)
        XCTAssertEqual(event.kindValue, .selectionChanged)
        XCTAssertEqual(event.familyKind, .document)
        XCTAssertEqual(event.selection?.primary.offset, 3)
        XCTAssertEqual(event.selection?.primarySelectionIndex, 0)
        XCTAssertEqual(event.selection?.selectionCount, 2)
        XCTAssertEqual(event.selection?.hasSelection, true)
        XCTAssertEqual(event.selection?.selections.first?.start, 1)
        XCTAssertEqual(event.selection?.selections.first?.end, 3)
        XCTAssertEqual(event.selection?.selections.first?.anchor, 1)
        XCTAssertEqual(event.selection?.selections.first?.active, 3)
        XCTAssertNil(event.text)
        XCTAssertNil(event.dirty)
    }

    func testEditorUIStateEventsRecordLayoutChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 14, lineHeightPx: 20, cellWidthPx: 9, paddingXPx: 3, paddingYPx: 4)
        var snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].familyKind, .document)
        XCTAssertEqual(snapshot.events[0].layout?.widthPx, 800)
        XCTAssertEqual(snapshot.events[0].layout?.heightPx, 600)
        XCTAssertEqual(snapshot.events[0].layout?.fontSize, 14)
        XCTAssertEqual(snapshot.events[0].layout?.lineHeightPx, 20)
        XCTAssertEqual(snapshot.events[0].layout?.cellWidthPx, 9)
        XCTAssertEqual(snapshot.events[0].layout?.paddingXPx, 3)
        XCTAssertEqual(snapshot.events[0].layout?.paddingYPx, 4)
        XCTAssertEqual(snapshot.events[0].layout?.tabWidthCells, 4)
        XCTAssertEqual(snapshot.events[0].layout?.textVerticalAlign, "center")
        XCTAssertNil(snapshot.events[0].viewport)

        try ui.setTextVerticalAlign(.bottom)
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 2)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].layout?.textVerticalAlign, "bottom")

        try ui.setTabWidth(2)
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 3)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].layout?.tabWidthCells, 2)
    }

    func testEditorUIStateEventsRecordViewportChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(
            library: lib,
            initialText: "one\ntwo\nthree\nfour\nfive",
            viewportWidthCells: 80
        )

        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        let baseline = try ui.stateEventsLatestSequence()
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        let resize = try ui.stateEvents(after: baseline)
        XCTAssertEqual(resize.events.map(\.kindValue), [.viewportChanged, .layoutChanged])
        let resizeEvent = try XCTUnwrap(resize.events.first { $0.kindValue == .viewportChanged })
        XCTAssertEqual(resizeEvent.familyKind, .document)
        XCTAssertEqual(resizeEvent.viewport?.width, 8)
        XCTAssertEqual(resizeEvent.viewport?.height, 2)
        XCTAssertEqual(resizeEvent.viewport?.scrollTop, 0)
        XCTAssertEqual(resizeEvent.viewport?.visibleLines.start, 0)
        XCTAssertEqual(resizeEvent.viewport?.visibleLines.end, 2)
        XCTAssertNil(resizeEvent.text)
        XCTAssertNil(resizeEvent.dirty)
        XCTAssertNil(resizeEvent.selection)

        ui.setSmoothScrollState(topVisualRow: 1, subRowOffset: 32768)
        let scrolled = try ui.stateEvents(after: resize.latestSequence)
        XCTAssertEqual(scrolled.events.count, 1)
        XCTAssertEqual(scrolled.events[0].kindValue, .viewportChanged)
        XCTAssertEqual(scrolled.events[0].viewport?.scrollTop, 1)
        XCTAssertEqual(scrolled.events[0].viewport?.subRowOffset, 32768)
        XCTAssertEqual(scrolled.events[0].viewport?.visibleLines.start, 1)
    }

    func testEditorUIStateEventsRecordDerivedStateChangesAndStale() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        try ui.lspApplyDiagnosticsJSON("""
        {
          "uri": "file:///tmp/main.rs",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }
        """)

        let changed = try ui.stateEvents()
        XCTAssertEqual(changed.latestSequence, 1)
        XCTAssertEqual(changed.events.count, 1)
        XCTAssertEqual(changed.events[0].kindValue, .derivedStateChanged)
        XCTAssertEqual(changed.events[0].familyKind, .derivedState)
        XCTAssertEqual(changed.events[0].derivedState?.status, "changed")
        XCTAssertEqual(changed.events[0].derivedState?.reason, "processing_edits")
        XCTAssertEqual(changed.events[0].derivedState?.textVersion, 0)
        XCTAssertEqual(changed.events[0].derivedState?.editCount, 2)
        XCTAssertEqual(changed.events[0].derivedState?.families, ["style_intervals", "diagnostics"])
        XCTAssertNil(changed.events[0].text)
        XCTAssertNil(changed.events[0].dirty)

        try ui.insertText("z")
        let stale = try ui.stateEvents(after: changed.latestSequence)
        XCTAssertEqual(stale.events.map(\.kindValue), [
            .dirtyChanged,
            .selectionChanged,
            .textChanged,
            .derivedStateStale,
        ])
        let staleEvent = try XCTUnwrap(stale.events.last)
        XCTAssertEqual(staleEvent.familyKind, .derivedState)
        XCTAssertEqual(staleEvent.derivedState?.status, "stale")
        XCTAssertEqual(staleEvent.derivedState?.reason, "text_changed")
        XCTAssertEqual(staleEvent.derivedState?.textVersion, 1)
        XCTAssertEqual(staleEvent.derivedState?.editCount, 0)
        XCTAssertEqual(staleEvent.derivedState?.families.last, "document_symbols")
    }
}
