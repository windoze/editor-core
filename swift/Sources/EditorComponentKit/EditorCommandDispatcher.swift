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
    public var customCommandHandler: ((String, [String: String]) -> EditorCommandResult?)?

    public init(engine: EditorEngineProtocol? = nil) {
        self.engine = engine
    }

    public func dispatch(_ command: EditorCommand) {
        if case .custom(let name, let payload) = command,
           let handledResult = customCommandHandler?(name, payload) {
            observer?.commandDispatcher(self, didSucceed: handledResult)
            return
        }

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
