import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorPreferencesApplicationTests: XCTestCase {
    func testWrapModePreferenceAppliesToNewEditor() throws {
        let noWrap = try openEditor(wrapMode: .none)
        try noWrap.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(noWrap.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })

        let charWrap = try openEditor(wrapMode: .char)
        try charWrap.editor.setViewportWidthCells(4)
        XCTAssertTrue(try viewportLines(charWrap.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
    }

    func testWrapIndentPreferenceAppliesToNewEditor() throws {
        let fixedIndent = try openEditor(wrapMode: .char, wrapIndent: .fixedCells(2))
        try fixedIndent.editor.setViewportWidthCells(4)

        let wrappedLines = try viewportLines(fixedIndent.editor).filter {
            ($0["is_wrapped_part"] as? Bool) == true
        }
        XCTAssertTrue(wrappedLines.contains { ($0["segment_x_start_cells"] as? Int) == 2 })
    }

    private func openEditor(
        wrapMode: EcuWrapMode,
        wrapIndent: EcuWrapIndent? = nil
    ) throws -> EditorCoreSkiaView {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorPreferencesApplicationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = tempDir.appendingPathComponent("wrap.txt")
        try "abcdefghijklmnop\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let prefs = makeIsolatedPreferences(wrapMode: wrapMode, wrapIndent: wrapIndent)
        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            preferences: prefs
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        vc.openFile(url: fileURL, mode: .pinned)

        return try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
    }

    private func makeIsolatedPreferences(
        wrapMode: EcuWrapMode,
        wrapIndent: EcuWrapIndent?
    ) -> AttoPreferences {
        let suiteName = "atto_editor_preferences_application_tests_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults(suiteName:)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        prefs.setWrapMode(wrapMode)
        if let wrapIndent {
            prefs.setWrapIndent(wrapIndent)
        }
        return prefs
    }

    private func viewportLines(_ editor: EditorUI) throws -> [[String: Any]] {
        let json = try editor.viewportJSON(startRow: 0, count: 20)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
        return try XCTUnwrap(viewport["lines"] as? [[String: Any]])
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }
}
