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

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspStartPlanEntry {
    pub operation: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspStopPlanEntry {
    pub operation: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspRestartPlanEntry {
    pub operation: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProjectLspOpenDocument {
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: Option<String>,
    pub language_id: Option<String>,
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

pub(crate) fn project_lsp_start_plan(
    configs: &BTreeMap<String, ProjectLspServerConfig>,
    workspace_roots: &[String],
    documents: impl IntoIterator<Item = ProjectLspOpenDocument>,
) -> Vec<ProjectLspStartPlanEntry> {
    let fallback_workspace_roots = normalize_project_lsp_workspace_roots(workspace_roots.to_vec());
    let mut entries = Vec::new();

    for document in documents {
        let Some(document_uri) = normalize_non_empty(document.document_uri.as_deref()) else {
            continue;
        };
        let Some(language_id) = normalize_non_empty(document.language_id.as_deref()) else {
            continue;
        };

        for config in configs.values() {
            if config.auto_start == false
                || config.language_id.eq_ignore_ascii_case(&language_id) == false
            {
                continue;
            }
            let workspace_roots = if config.workspace_roots.is_empty() {
                fallback_workspace_roots.clone()
            } else {
                config.workspace_roots.clone()
            };
            entries.push(ProjectLspStartPlanEntry {
                operation: "start".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
            });
        }
    }

    entries
}

pub(crate) fn project_lsp_stop_plan(
    configs: &BTreeMap<String, ProjectLspServerConfig>,
    workspace_roots: &[String],
    documents: impl IntoIterator<Item = ProjectLspOpenDocument>,
) -> Vec<ProjectLspStopPlanEntry> {
    let fallback_workspace_roots = normalize_project_lsp_workspace_roots(workspace_roots.to_vec());
    let mut entries = Vec::new();

    for document in documents {
        let Some(document_uri) = normalize_non_empty(document.document_uri.as_deref()) else {
            continue;
        };
        let Some(language_id) = normalize_non_empty(document.language_id.as_deref()) else {
            continue;
        };

        for config in configs.values() {
            if config.language_id.eq_ignore_ascii_case(&language_id) == false {
                continue;
            }
            let workspace_roots = if config.workspace_roots.is_empty() {
                fallback_workspace_roots.clone()
            } else {
                config.workspace_roots.clone()
            };
            entries.push(ProjectLspStopPlanEntry {
                operation: "stop".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
            });
        }
    }

    entries
}

pub(crate) fn project_lsp_restart_plan(
    configs: &BTreeMap<String, ProjectLspServerConfig>,
    workspace_roots: &[String],
    documents: impl IntoIterator<Item = ProjectLspOpenDocument>,
) -> Vec<ProjectLspRestartPlanEntry> {
    let fallback_workspace_roots = normalize_project_lsp_workspace_roots(workspace_roots.to_vec());
    let mut entries = Vec::new();

    for document in documents {
        let Some(document_uri) = normalize_non_empty(document.document_uri.as_deref()) else {
            continue;
        };
        let Some(language_id) = normalize_non_empty(document.language_id.as_deref()) else {
            continue;
        };

        for config in configs.values() {
            if config.language_id.eq_ignore_ascii_case(&language_id) == false {
                continue;
            }
            let workspace_roots = if config.workspace_roots.is_empty() {
                fallback_workspace_roots.clone()
            } else {
                config.workspace_roots.clone()
            };
            entries.push(ProjectLspRestartPlanEntry {
                operation: "restart".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
            });
        }
    }

    entries
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

fn normalize_non_empty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
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
