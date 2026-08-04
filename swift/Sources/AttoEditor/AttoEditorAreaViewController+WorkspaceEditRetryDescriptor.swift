import Foundation

extension AttoEditorAreaViewController {
    func workspaceEditRequestRetryDescriptor(
        kind: AttoWorkspaceEditRequestRetryDescriptor.Kind,
        label: String,
        tabID: UUID,
        documentURI fallbackDocumentURI: String? = nil,
        parameterSummary: [AttoWorkspaceEditRequestRetryDescriptor.Parameter]
    ) -> AttoWorkspaceEditRequestRetryDescriptor {
        let source = workspaceEditRequestRetrySource(
            tabID: tabID,
            fallbackDocumentURI: fallbackDocumentURI
        )
        return AttoWorkspaceEditRequestRetryDescriptor(
            kind: kind,
            label: label,
            workspaceRootURI: workspaceRootURL.standardizedFileURL.absoluteString,
            documentURI: source.documentURI ?? fallbackDocumentURI,
            source: source,
            parameterSummary: parameterSummary,
            invalidationReason: nil
        )
    }

    func workspaceEditRequestRetrySource(
        tabID: UUID,
        fallbackDocumentURI: String?
    ) -> AttoWorkspaceEditRequestRetryDescriptor.Source {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return AttoWorkspaceEditRequestRetryDescriptor.Source(
                tabID: tabID,
                coreTabID: nil,
                title: nil,
                documentURI: fallbackDocumentURI
            )
        }

        let documentURL = projectedFileURL(for: tab).standardizedFileURL
        return AttoWorkspaceEditRequestRetryDescriptor.Source(
            tabID: tab.id,
            coreTabID: tab.coreTabID,
            title: documentURL.lastPathComponent.isEmpty ? documentURL.path : documentURL.lastPathComponent,
            documentURI: fallbackDocumentURI ?? documentURL.absoluteString
        )
    }

    func workspaceEditRequestKind(
        for kind: FormattingRequestKind
    ) -> AttoWorkspaceEditRequestRetryDescriptor.Kind {
        switch kind {
        case .document:
            return .formatDocument
        case .selection:
            return .formatSelection
        }
    }

    func formattingWorkspaceEditRequestParameters(
        _ context: FormattingRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        var parameters: [AttoWorkspaceEditRequestRetryDescriptor.Parameter] = [
            .parameter("showFeedback", context.showFeedback),
        ]
        if case .selection(let startOffset, let endOffset) = context.kind {
            parameters.append(.parameter("startOffset", startOffset))
            parameters.append(.parameter("endOffset", endOffset))
        }
        return parameters
    }

    func colorPresentationWorkspaceEditRequestParameters(
        _ context: ColorPresentationRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .parameter("line", context.item.startLine),
            .parameter("utf16Character", context.item.startUTF16Character),
            .parameter("range", "\(context.item.range.start)..\(context.item.range.end)"),
            .parameter("color", AttoLspDocumentColorParser.hexString(for: context.item.color)),
            .parameter("showFeedback", context.showFeedback),
        ]
    }

    func inlayHintResolveWorkspaceEditRequestParameters(
        _ context: InlayHintResolveContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .jsonParameter("hint", context.hintJSON),
            .parameter("showFeedback", context.showFeedback),
        ]
    }

    func executeCommandWorkspaceEditRequestParameters(
        _ context: ExecuteCommandRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .parameter("title", context.commandTitle),
            .jsonParameter("command", context.commandJSON),
        ]
    }

    func completionWorkspaceEditRequestParameters(
        _ context: CompletionRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .parameter("logicalLine", context.logicalLine),
            .parameter("logicalColumn", context.logicalColumn),
            .parameter("fallbackStart", context.fallbackStart),
            .parameter("fallbackEnd", context.fallbackEnd),
            .parameter("beepOnFailure", context.beepOnFailure),
            .parameter("showFeedback", context.showFeedback),
        ]
    }

    func codeActionWorkspaceEditRequestParameters(
        _ context: CodeActionRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .parameter("startOffset", context.startOffset),
            .parameter("endOffset", context.endOffset),
            .parameter("onlyKinds", context.onlyKinds.joined(separator: ",")),
            .parameter("showFeedback", context.showFeedback),
        ]
    }

    func renameWorkspaceEditRequestParameters(
        _ context: RenameRequestContext
    ) -> [AttoWorkspaceEditRequestRetryDescriptor.Parameter] {
        [
            .parameter("logicalLine", context.logicalLine),
            .parameter("logicalColumn", context.logicalColumn),
            .parameter("newName", context.newName),
            .parameter("showFeedback", context.showFeedback),
        ]
    }
}
