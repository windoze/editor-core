pub(crate) fn lsp_signature_help_capability_json(
    capabilities: &serde_json::Value,
) -> serde_json::Value {
    let provider = capabilities.get("signatureHelpProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let retrigger_characters =
        lsp_string_array(provider.and_then(|p| p.get("retriggerCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "retrigger_characters": retrigger_characters,
    })
}

pub(crate) fn lsp_completion_capability_json(
    capabilities: &serde_json::Value,
) -> serde_json::Value {
    let provider = capabilities.get("completionProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let all_commit_characters =
        lsp_string_array(provider.and_then(|p| p.get("allCommitCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "all_commit_characters": all_commit_characters,
    })
}

pub(crate) fn lsp_string_array(value: Option<&serde_json::Value>) -> Vec<String> {
    value
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(ToString::to_string))
                .collect()
        })
        .unwrap_or_default()
}
