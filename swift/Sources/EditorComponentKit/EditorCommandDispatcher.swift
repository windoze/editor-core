import Foundation

@MainActor
public protocol EditorCommandDispatching: AnyObject {
    func dispatch(_ command: EditorCommand)
}

@MainActor
public protocol EditorCommandDispatchObserver: AnyObject {
    func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didFail error: EditorCommandError)
    func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didSucceed result: EditorCommandResult)
}

@MainActor
public final class EditorCommandDispatcher: EditorCommandDispatching {
    public weak var observer: EditorCommandDispatchObserver?
    public weak var engine: EditorEngineProtocol?

    public init(engine: EditorEngineProtocol? = nil) {
        self.engine = engine
    }

    public func dispatch(_ command: EditorCommand) {
        guard let engine else {
            observer?.commandDispatcher(self, didFail: EditorCommandError("No engine attached"))
            return
        }

        do {
            let result = try engine.execute(command)
            observer?.commandDispatcher(self, didSucceed: result)
        } catch {
            observer?.commandDispatcher(
                self,
                didFail: EditorCommandError("Failed to execute command: \(error)")
            )
        }
    }
}
