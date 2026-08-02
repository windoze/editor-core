mod display;
mod response_method;
mod wire;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum LspResultSlot {
    Hover,
    Definition,
    Declaration,
    TypeDefinition,
    Implementation,
    References,
    Completion,
    CompletionResolve,
    SignatureHelp,
    PrepareRename,
    Rename,
    CodeAction,
    CodeActionResolve,
    ExecuteCommand,
    CodeLens,
    CodeLensResolve,
    InlayHints,
    InlayHintResolve,
    DocumentLinks,
    DocumentLinkResolve,
    SemanticTokensFull,
    SemanticTokensDelta,
    SemanticTokensRange,
    DocumentSymbols,
    WorkspaceSymbols,
    FoldingRanges,
    SelectionRange,
    LinkedEditingRange,
    DocumentDiagnostic,
    WorkspaceDiagnostic,
    PublishDiagnostics,
    DocumentColor,
    ColorPresentation,
    PrepareCallHierarchy,
    CallHierarchyIncoming,
    CallHierarchyOutgoing,
    PrepareTypeHierarchy,
    TypeHierarchySupertypes,
    TypeHierarchySubtypes,
    OnTypeFormatting,
}

impl LspResultSlot {
    pub(crate) fn from_response_method(method: &str) -> Option<Self> {
        response_method::from_response_method(method)
    }

    pub(crate) fn method(self) -> &'static str {
        wire::method(self)
    }

    pub(crate) fn slot_name(self) -> &'static str {
        wire::slot_name(self)
    }

    pub(crate) fn family(self) -> &'static str {
        display::family(self)
    }

    pub(crate) fn title(self) -> &'static str {
        display::title(self)
    }
}
