import Foundation

extension AttoEditorAreaViewController {
    static let xcuiResultFixturesEnvKey = "ATTO_XCUI_RESULT_FIXTURES"

    func installXCUISmokeResultFixturesIfEnabled(for tab: AttoEditorTab) {
        guard Self.xcuiResultFixturesEnabled() else { return }

        let documentURL = projectedFileURL(for: tab).standardizedFileURL
        let documentURI = documentURL.absoluteString
        let primaryTarget = AttoLspDefinitionParser.Target(uri: documentURI, line: 0, utf16Character: 0)
        let secondaryTarget = AttoLspDefinitionParser.Target(uri: documentURI, line: 1, utf16Character: 2)
        let locationItems = AttoLspDefinitionParser.locationItems(
            for: [primaryTarget, secondaryTarget],
            workspaceRootURL: workspaceRootURL
        )
        recordLspLocationResultSnapshot(LspLocationResultSnapshot(kind: .references, items: locationItems))

        let symbolsJSON = """
        [
          {
            "name": "XCUISmokeDocument",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 0 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 16 }
            },
            "children": [
              {
                "name": "smokeChild",
                "kind": 12,
                "range": {
                  "start": { "line": 1, "character": 0 },
                  "end": { "line": 1, "character": 10 }
                },
                "selectionRange": {
                  "start": { "line": 1, "character": 0 },
                  "end": { "line": 1, "character": 10 }
                }
              }
            ]
          }
        ]
        """
        try? tab.editCore.editor.lspApplyDocumentSymbolsJSON(symbolsJSON)
        applyCoreDocumentSymbols(tab: tab, json: symbolsJSON)
        derivedStateStore.refreshActive(editor: tab.editCore.editor)

        let text = (try? tab.editCore.editor.text()) ?? ""
        let typedSymbols = AttoLspSymbolParser.documentSymbols(
            snapshot: derivedStateStore.active.documentSymbols,
            documentURI: documentURI,
            documentText: text
        )
        let symbols = typedSymbols.isEmpty
            ? AttoLspSymbolParser.documentSymbols(fromResultJSON: symbolsJSON, documentURI: documentURI)
            : typedSymbols
        updateWorkspaceOutline(tab: tab, documentText: text, symbols: symbols)
        recordLspSymbolResultSnapshot(LspSymbolResultSnapshot(
            title: "Document Symbols",
            symbols: symbols,
            placeholder: "Filter document symbols..."
        ))
    }

    private static func xcuiResultFixturesEnabled() -> Bool {
        guard let value = ProcessInfo.processInfo.environment[xcuiResultFixturesEnvKey] else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
