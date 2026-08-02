use crate::UiError;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspServerConfig {
    #[serde(default)]
    pub key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub language_id: String,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default = "default_auto_start")]
    pub auto_start: bool,
}

fn default_auto_start() -> bool {
    true
}

pub(crate) fn normalize_project_lsp_servers(
    configs: Vec<ProjectLspServerConfig>,
) -> Result<BTreeMap<String, ProjectLspServerConfig>, UiError> {
    let mut out = BTreeMap::new();
    for config in configs {
        let normalized = normalize_project_lsp_server(config)?;
        out.insert(normalized.key.clone(), normalized);
    }
    Ok(out)
}

fn normalize_project_lsp_server(
    config: ProjectLspServerConfig,
) -> Result<ProjectLspServerConfig, UiError> {
    let command = config.command.trim().to_string();
    if command.is_empty() {
        return Err(UiError::Processor(
            "project LSP server command cannot be empty".to_string(),
        ));
    }

    let language_id = config.language_id.trim().to_string();
    let key = normalize_project_lsp_server_key(&config.key, &language_id, &command)?;
    let args = config
        .args
        .into_iter()
        .map(|arg| arg.trim().to_string())
        .filter(|arg| !arg.is_empty())
        .collect();
    let workspace_roots = normalize_project_lsp_workspace_roots(config.workspace_roots);

    Ok(ProjectLspServerConfig {
        key,
        command,
        args,
        language_id,
        workspace_roots,
        auto_start: config.auto_start,
    })
}

fn normalize_project_lsp_server_key(
    raw_key: &str,
    language_id: &str,
    command: &str,
) -> Result<String, UiError> {
    let key = first_non_empty([raw_key, language_id, command])
        .ok_or_else(|| UiError::Processor("project LSP server key cannot be empty".to_string()))?;
    Ok(key.to_ascii_lowercase())
}

fn normalize_project_lsp_workspace_roots(roots: Vec<String>) -> Vec<String> {
    let mut seen = BTreeMap::new();
    for root in roots {
        let trimmed = root.trim();
        if trimmed.is_empty() {
            continue;
        }
        seen.entry(trimmed.to_string()).or_insert(());
    }
    seen.into_keys().collect()
}

fn first_non_empty<'a>(values: impl IntoIterator<Item = &'a str>) -> Option<&'a str> {
    values
        .into_iter()
        .map(str::trim)
        .find(|value| !value.is_empty())
}
