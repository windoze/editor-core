use super::LspResultSlot;

pub(super) fn family(slot: LspResultSlot) -> &'static str {
    match slot {
        LspResultSlot::Hover => "hover",
        LspResultSlot::Definition
        | LspResultSlot::Declaration
        | LspResultSlot::TypeDefinition
        | LspResultSlot::Implementation
        | LspResultSlot::References => "locations",
        LspResultSlot::Completion
        | LspResultSlot::CompletionResolve
        | LspResultSlot::SignatureHelp => "completion",
        LspResultSlot::PrepareRename | LspResultSlot::Rename => "rename",
        LspResultSlot::CodeAction
        | LspResultSlot::CodeActionResolve
        | LspResultSlot::ExecuteCommand => "actions",
        LspResultSlot::CodeLens | LspResultSlot::CodeLensResolve => "code_lens",
        LspResultSlot::InlayHints | LspResultSlot::InlayHintResolve => "inlay_hints",
        LspResultSlot::DocumentLinks | LspResultSlot::DocumentLinkResolve => "document_links",
        LspResultSlot::SemanticTokensFull
        | LspResultSlot::SemanticTokensDelta
        | LspResultSlot::SemanticTokensRange => "semantic_tokens",
        LspResultSlot::DocumentSymbols | LspResultSlot::WorkspaceSymbols => "symbols",
        LspResultSlot::FoldingRanges
        | LspResultSlot::SelectionRange
        | LspResultSlot::LinkedEditingRange => "ranges",
        LspResultSlot::DocumentDiagnostic
        | LspResultSlot::WorkspaceDiagnostic
        | LspResultSlot::PublishDiagnostics => "diagnostics",
        LspResultSlot::Formatting
        | LspResultSlot::RangeFormatting
        | LspResultSlot::OnTypeFormatting => "formatting",
        LspResultSlot::DocumentColor | LspResultSlot::ColorPresentation => "colors",
        LspResultSlot::PrepareCallHierarchy
        | LspResultSlot::CallHierarchyIncoming
        | LspResultSlot::CallHierarchyOutgoing => "call_hierarchy",
        LspResultSlot::PrepareTypeHierarchy
        | LspResultSlot::TypeHierarchySupertypes
        | LspResultSlot::TypeHierarchySubtypes => "type_hierarchy",
    }
}

pub(super) fn title(slot: LspResultSlot) -> &'static str {
    match slot {
        LspResultSlot::Hover => "LSP Hover",
        LspResultSlot::Definition => "LSP Definition",
        LspResultSlot::Declaration => "LSP Declaration",
        LspResultSlot::TypeDefinition => "LSP Type Definition",
        LspResultSlot::Implementation => "LSP Implementation",
        LspResultSlot::References => "LSP References",
        LspResultSlot::Completion => "LSP Completion",
        LspResultSlot::CompletionResolve => "LSP Completion Resolve",
        LspResultSlot::SignatureHelp => "LSP Signature Help",
        LspResultSlot::PrepareRename => "LSP Prepare Rename",
        LspResultSlot::Rename => "LSP Rename",
        LspResultSlot::CodeAction => "LSP Code Action",
        LspResultSlot::CodeActionResolve => "LSP Code Action Resolve",
        LspResultSlot::ExecuteCommand => "LSP Execute Command",
        LspResultSlot::CodeLens => "LSP Code Lens",
        LspResultSlot::CodeLensResolve => "LSP Code Lens Resolve",
        LspResultSlot::InlayHints => "LSP Inlay Hints",
        LspResultSlot::InlayHintResolve => "LSP Inlay Hint Resolve",
        LspResultSlot::DocumentLinks => "LSP Document Links",
        LspResultSlot::DocumentLinkResolve => "LSP Document Link Resolve",
        LspResultSlot::SemanticTokensFull => "LSP Semantic Tokens Full",
        LspResultSlot::SemanticTokensDelta => "LSP Semantic Tokens Delta",
        LspResultSlot::SemanticTokensRange => "LSP Semantic Tokens Range",
        LspResultSlot::DocumentSymbols => "LSP Document Symbols",
        LspResultSlot::WorkspaceSymbols => "LSP Workspace Symbols",
        LspResultSlot::FoldingRanges => "LSP Folding Ranges",
        LspResultSlot::SelectionRange => "LSP Selection Range",
        LspResultSlot::LinkedEditingRange => "LSP Linked Editing Range",
        LspResultSlot::DocumentDiagnostic => "LSP Document Diagnostic",
        LspResultSlot::WorkspaceDiagnostic => "LSP Workspace Diagnostic",
        LspResultSlot::PublishDiagnostics => "LSP Publish Diagnostics",
        LspResultSlot::Formatting => "LSP Formatting",
        LspResultSlot::RangeFormatting => "LSP Range Formatting",
        LspResultSlot::DocumentColor => "LSP Document Color",
        LspResultSlot::ColorPresentation => "LSP Color Presentation",
        LspResultSlot::PrepareCallHierarchy => "LSP Prepare Call Hierarchy",
        LspResultSlot::CallHierarchyIncoming => "LSP Call Hierarchy Incoming",
        LspResultSlot::CallHierarchyOutgoing => "LSP Call Hierarchy Outgoing",
        LspResultSlot::PrepareTypeHierarchy => "LSP Prepare Type Hierarchy",
        LspResultSlot::TypeHierarchySupertypes => "LSP Type Hierarchy Supertypes",
        LspResultSlot::TypeHierarchySubtypes => "LSP Type Hierarchy Subtypes",
        LspResultSlot::OnTypeFormatting => "LSP On-Type Formatting",
    }
}
