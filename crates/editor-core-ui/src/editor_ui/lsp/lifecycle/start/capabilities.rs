pub(super) fn default_initialize_params(root_uri: &str) -> serde_json::Value {
    let token_types = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_TYPES;
    let token_modifiers = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_MODIFIERS;
    serde_json::json!({
        "processId": std::process::id(),
        "rootUri": root_uri,
        "capabilities": {
            "textDocument": {
                "semanticTokens": {
                    "dynamicRegistration": false,
                    "requests": { "range": false, "full": { "delta": false } },
                    "tokenTypes": token_types,
                    "tokenModifiers": token_modifiers,
                    "formats": ["relative"],
                    "multilineTokenSupport": true,
                    "overlappingTokenSupport": false,
                },
                "foldingRange": {
                    "dynamicRegistration": false,
                    "lineFoldingOnly": true,
                },
                "inlayHint": { "dynamicRegistration": false },
                "codeLens": { "dynamicRegistration": false },
                "documentLink": { "dynamicRegistration": false },
            },
        },
        "clientInfo": { "name": "editor-core ui" },
    })
}
