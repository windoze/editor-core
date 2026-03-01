#if canImport(AppKit)
import AppKit
import XCTest
@testable import EditorComponentKit

@MainActor
final class EditorInteractionTests: XCTestCase {
    final class Delegate: EditorComponentDelegate {
        var lastError: EditorCommandError?
        var lastResult: EditorCommandResult?

        func editorComponent(_ component: EditorComponentView, didFail error: EditorCommandError) {
            lastError = error
        }

        func editorComponent(_ component: EditorComponentView, didExecute commandResult: EditorCommandResult) {
            lastResult = commandResult
        }
    }

    final class HoverProvider: EditorHoverProvider {
        func editorComponent(_ component: EditorComponentView, hoverAt position: EditorPosition) -> EditorHoverTooltip? {
            EditorHoverTooltip(title: "Type", message: "Hover @ \(position.line):\(position.column)")
        }
    }

    final class MenuProvider: EditorContextMenuProvider {
        func editorComponent(
            _ component: EditorComponentView,
            contextMenuItemsAt position: EditorPosition
        ) -> [EditorContextMenuItem] {
            [
                EditorContextMenuItem(
                    title: "Insert TODO",
                    command: .insertText("// TODO")
                ),
                .separator,
                EditorContextMenuItem(title: "Log Position") {}
            ]
        }
    }

    func testCustomCommandHandlerCanBypassEngine() {
        let component = EditorComponentView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let delegate = Delegate()
        component.delegate = delegate
        component.customCommandHandler = { name, payload in
            .text("custom:\(name):\(payload["k"] ?? "")")
        }

        component.dispatch(.custom(name: "showPalette", payload: ["k": "v"]))

        XCTAssertEqual(delegate.lastResult, .text("custom:showPalette:v"))
        XCTAssertNil(delegate.lastError)
    }

    func testHoverAndContextMenuProvidersAreWiredToTextView() {
        let component = EditorComponentView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let hoverProvider = HoverProvider()
        let menuProvider = MenuProvider()
        component.hoverProvider = hoverProvider
        component.contextMenuProvider = menuProvider

        let hover = component.textViewForTesting.hoverTooltipProvider?(.init(line: 2, column: 5))
        XCTAssertEqual(hover?.title, "Type")
        XCTAssertEqual(hover?.message, "Hover @ 2:5")

        let menuItems = component.textViewForTesting.contextMenuProvider?(.init(line: 1, column: 3))
        XCTAssertEqual(menuItems?.count, 3)
        XCTAssertEqual(menuItems?.first?.title, "Insert TODO")
    }

    func testComponentBindAndUnbindKey() {
        let component = EditorComponentView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let chord = EditorKeyChord(key: "k", modifiers: [.command, .shift])
        component.bindKey(chord, to: .custom(name: "openCommandPalette", payload: [:]))
        XCTAssertEqual(
            component.keybindingRegistry.resolve(chord),
            .custom(name: "openCommandPalette", payload: [:])
        )

        component.unbindKey(chord)
        XCTAssertNil(component.keybindingRegistry.resolve(chord))
    }
}
#endif
