import AppKit
import EditorCoreUI
import Foundation

extension AttoEditorAreaViewController {
    var defaultLSPFormattingOptionsJSON: String {
        #"{ "tabSize": 4, "insertSpaces": true }"#
    }

    @discardableResult
    func requestFormattingWithLspInActiveTab(
        kind: FormattingRequestKind,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let feature = kind.feedbackFeature
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(feature), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelFormattingUI()
        do {
            switch kind {
            case .document:
                _ = try tab.editCore.editor.lspRequestFormatting(
                    formattingOptionsJSON: defaultLSPFormattingOptionsJSON
                )
            case .selection(let startOffset, let endOffset):
                _ = try tab.editCore.editor.lspRequestRangeFormatting(
                    startOffset: startOffset,
                    endOffset: endOffset,
                    formattingOptionsJSON: defaultLSPFormattingOptionsJSON
                )
            }
        } catch {
            cancelFormattingUI()
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(feature, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        formattingContext = FormattingRequestContext(tabID: tab.id, kind: kind, showFeedback: showFeedback)
        tab.editCore.editorView.kickProcessingPoll()
        updateStatusBar()
        startFormattingPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    func startFormattingPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        formattingPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.formattingContext, ctx.tabID == tabID else {
                self.cancelFormattingUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelFormattingUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(feature), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelFormattingUI()
                return
            }

            do {
                _ = try tab.editCore.editor.pollProcessing()
            } catch {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelFormattingUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            let resultJSON: String?
            do {
                switch ctx.kind {
                case .document:
                    resultJSON = try tab.editCore.editor.lspTakeLastFormattingResultJSON()
                case .selection:
                    resultJSON = try tab.editCore.editor.lspTakeLastRangeFormattingResultJSON()
                }
            } catch {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelFormattingUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            guard let resultJSON else { return }

            self.cancelFormattingRequestOnly()
            _ = self.applyFormattingResultJSON(resultJSON, context: ctx, tab: tab)
        }

        formattingPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func applyFormattingResultJSON(
        _ resultJSON: String,
        context: FormattingRequestContext,
        tab: AttoEditorTab
    ) -> Bool {
        let feature = context.kind.feedbackFeature
        let documentURI = projectedFileURL(for: tab).absoluteString

        do {
            guard let workspaceEditJSON = try formattingWorkspaceEditJSON(
                fromTextEditResultJSON: resultJSON,
                documentURI: documentURI
            ) else {
                if context.showFeedback {
                    presentLspResultFeedback(AttoLspResultFeedback.empty(feature), in: tab.editCore.editorView)
                }
                NSSound.beep()
                return false
            }

            guard let parsed = AttoWorkspaceEditParser.parse(workspaceEditJSON),
                  parsed.isEmpty == false
            else {
                if context.showFeedback {
                    presentLspResultFeedback(
                        AttoLspResultFeedback.failed(
                            feature,
                            errorDescription: "Formatting result could not be converted to a WorkspaceEdit."
                        ),
                        in: tab.editCore.editorView
                    )
                }
                NSSound.beep()
                return false
            }

            let outcome = applyWorkspaceEditToActiveTab(
                parsed,
                workspaceEditJSON: workspaceEditJSON,
                documentURI: documentURI,
                requestRetryOwner: formattingWorkspaceEditRequestRetryOwner(context: context)
            )
            return outcome.accepted
        } catch {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func formattingWorkspaceEditJSON(
        fromTextEditResultJSON resultJSON: String,
        documentURI: String
    ) throws -> String? {
        guard let data = resultJSON.data(using: .utf8) else {
            throw formattingError("Formatting result is not valid UTF-8.")
        }

        let value = try JSONSerialization.jsonObject(with: data, options: [])
        if value is NSNull {
            return nil
        }
        guard let edits = value as? [[String: Any]] else {
            throw formattingError("Formatting result must be a TextEdit array.")
        }
        guard edits.isEmpty == false else {
            return nil
        }

        let root: [String: Any] = [
            "changes": [
                documentURI: edits,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(root) else {
            throw formattingError("Formatting result could not be encoded as a WorkspaceEdit.")
        }

        let workspaceData = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let workspaceEditJSON = String(data: workspaceData, encoding: .utf8) else {
            throw formattingError("Formatting WorkspaceEdit is not valid UTF-8.")
        }
        return workspaceEditJSON
    }

    func formattingError(_ description: String) -> NSError {
        NSError(
            domain: "AttoEditor.LSPFormatting",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
