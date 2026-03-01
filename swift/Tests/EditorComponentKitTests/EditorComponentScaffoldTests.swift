import XCTest
@testable import EditorComponentKit

final class EditorKeybindingRegistryTests: XCTestCase {
    func testDefaultBindingsIncludeUndo() {
        let registry = EditorKeybindingRegistry()
        let command = registry.resolve(EditorKeyChord(key: "z", modifiers: [.command]))
        XCTAssertEqual(command, .undo)
    }

    func testCustomBindingOverridesDefault() {
        let registry = EditorKeybindingRegistry()
        registry.bind(EditorKeyChord(key: "z", modifiers: [.command]), command: .insertText("x"))

        let command = registry.resolve(EditorKeyChord(key: "z", modifiers: [.command]))
        XCTAssertEqual(command, .insertText("x"))
    }
}

@MainActor
final class EditorCommandDispatcherTests: XCTestCase {
    final class Observer: EditorCommandDispatchObserver {
        var lastError: EditorCommandError?
        var lastResult: EditorCommandResult?

        func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didFail error: EditorCommandError) {
            lastError = error
        }

        func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didSucceed result: EditorCommandResult) {
            lastResult = result
        }
    }

    func testDispatchWithEngine() {
        let engine = MockEditorEngine(text: "")
        let dispatcher = EditorCommandDispatcher(engine: engine)
        let observer = Observer()
        dispatcher.observer = observer

        dispatcher.dispatch(EditorCommand.insertText("hello"))

        XCTAssertEqual(observer.lastResult, .success)
        XCTAssertNil(observer.lastError)
        XCTAssertEqual(engine.text, "hello")
    }

    func testDispatchWithoutEngineReportsError() {
        let dispatcher = EditorCommandDispatcher(engine: nil)
        let observer = Observer()
        dispatcher.observer = observer

        dispatcher.dispatch(EditorCommand.insertText("hello"))

        XCTAssertNotNil(observer.lastError)
        XCTAssertNil(observer.lastResult)
    }

    func testDispatchCustomCommandUsesHandlerWhenProvided() {
        let dispatcher = EditorCommandDispatcher(engine: nil)
        let observer = Observer()
        dispatcher.observer = observer
        dispatcher.customCommandHandler = { name, payload in
            .text("\(name):\(payload["scope"] ?? "")")
        }

        dispatcher.dispatch(.custom(name: "palette", payload: ["scope": "editor"]))

        XCTAssertEqual(observer.lastResult, .text("palette:editor"))
        XCTAssertNil(observer.lastError)
    }
}

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorComponentViewTests: XCTestCase {
    func testComponentLoadsTextFromEngine() {
        let component = EditorComponentView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: .init(features: .init(showsMinimap: true))
        )
        let engine = MockEditorEngine(text: "line1\nline2")

        component.engine = engine
        component.layoutSubtreeIfNeeded()

        XCTAssertEqual(component.currentDisplayedText, "line1\nline2")
    }
}
#endif
