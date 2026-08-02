pub(super) fn default_initialize_params(root_uri: &str) -> serde_json::Value {
    let token_types = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_TYPES;
    let token_modifiers = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_MODIFIERS;
    let workspace_folders = default_workspace_folders(root_uri);
    serde_json::json!({
        "processId": std::process::id(),
        "rootUri": root_uri,
        "workspaceFolders": workspace_folders,
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

pub(super) fn default_workspace_folders(root_uri: &str) -> Vec<serde_json::Value> {
    let root_uri = root_uri.trim().trim_end_matches('/');
    if root_uri.is_empty() {
        return Vec::new();
    }

    vec![serde_json::json!({
        "uri": root_uri,
        "name": workspace_folder_name(root_uri),
    })]
}

fn workspace_folder_name(root_uri: &str) -> String {
    root_uri
        .rsplit('/')
        .find(|part| part.is_empty() == false)
        .unwrap_or("workspace")
        .to_string()
}
