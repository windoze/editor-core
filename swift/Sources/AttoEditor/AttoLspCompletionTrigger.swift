import Foundation
import EditorCoreUIFFI

enum AttoLspCompletionTrigger {
    static func shouldTrigger(committedText text: String, lspStatusJSON json: String) -> Bool {
        guard text.count == 1 else { return false }
        return triggerCharacters(fromLSPStatusJSON: json).contains(text)
    }

    static func shouldTrigger(committedText text: String, lspStatus: EcuLspStatusSnapshot) -> Bool {
        guard text.count == 1 else { return false }
        return triggerCharacters(from: lspStatus).contains(text)
    }

    static func triggerCharacters(fromLSPStatusJSON json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let status = try? JSONDecoder().decode(EcuLspStatusSnapshot.self, from: data)
        else { return [] }
        return triggerCharacters(from: status)
    }

    static func triggerCharacters(from status: EcuLspStatusSnapshot) -> Set<String> {
        guard let completion = status.capabilities?.completion, completion.supported else { return [] }
        return Set(completion.triggerCharacters.filter { $0.isEmpty == false })
    }
}
