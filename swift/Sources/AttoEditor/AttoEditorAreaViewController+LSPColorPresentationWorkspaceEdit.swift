import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    func applyColorPresentationWithWorkspaceEdit(
        _ presentation: AttoLspDocumentColorParser.Presentation,
        tab: AttoEditorTab,
        requestContext: ColorPresentationRequestContext?
    ) -> AttoWorkspaceEditApplyOutcome? {
        let documentURI = projectedFileURL(for: tab).absoluteString
        guard let documentText = try? tab.editCore.editor.text(),
              let workspaceEditJSON = colorPresentationWorkspaceEditJSON(
                  for: presentation,
                  documentText: documentText,
                  documentURI: documentURI
              ),
              let parsed = AttoWorkspaceEditParser.parse(workspaceEditJSON)
        else {
            return nil
        }

        return applyWorkspaceEditToActiveTab(
            parsed,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI,
            requestRetryOwner: requestContext.map {
                colorPresentationWorkspaceEditRequestRetryOwner(context: $0)
            }
        )
    }

    func colorPresentationWorkspaceEditJSON(
        for presentation: AttoLspDocumentColorParser.Presentation,
        documentText: String,
        documentURI: String
    ) -> String? {
        let editObjects = presentation.edits.compactMap {
            colorPresentationTextEditObject($0, documentText: documentText)
        }
        guard editObjects.count == presentation.edits.count else { return nil }

        let root: [String: Any] = [
            "changes": [
                documentURI: editObjects,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func colorPresentationTextEditObject(_ edit: EcuTextEdit, documentText: String) -> [String: Any]? {
        guard edit.start <= edit.end,
              Int(edit.end) <= documentText.unicodeScalars.count
        else {
            return nil
        }

        return [
            "range": [
                "start": colorPresentationLspPosition(in: documentText, charOffset: edit.start),
                "end": colorPresentationLspPosition(in: documentText, charOffset: edit.end),
            ],
            "newText": edit.text,
        ]
    }

    func colorPresentationLspPosition(in text: String, charOffset: UInt32) -> [String: Int] {
        let limit = min(Int(charOffset), text.unicodeScalars.count)
        var line = 0
        var utf16Column = 0

        for scalar in text.unicodeScalars.prefix(limit) {
            if scalar == "\n" {
                line += 1
                utf16Column = 0
            } else {
                utf16Column += String(scalar).utf16.count
            }
        }

        return ["line": line, "character": utf16Column]
    }
}
