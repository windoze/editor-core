use crate::UiError;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspWorkspaceFolder {
    pub uri: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub root_alias: Option<String>,
}

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
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
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
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspStopPlanEntry {
    pub operation: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspRestartPlanEntry {
    pub operation: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
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
    let (fallback_workspace_roots, fallback_workspace_folders) =
        normalize_project_lsp_workspace_schema(workspace_roots.to_vec(), Vec::new());
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
            let (workspace_roots, workspace_folders) = if config.workspace_roots.is_empty() {
                (
                    fallback_workspace_roots.clone(),
                    fallback_workspace_folders.clone(),
                )
            } else {
                (
                    config.workspace_roots.clone(),
                    config.workspace_folders.clone(),
                )
            };
            entries.push(ProjectLspStartPlanEntry {
                operation: "start".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                language_name: config.language_name.clone(),
                server_capabilities: config.server_capabilities.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
                workspace_folders,
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
    let (fallback_workspace_roots, fallback_workspace_folders) =
        normalize_project_lsp_workspace_schema(workspace_roots.to_vec(), Vec::new());
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
            let (workspace_roots, workspace_folders) = if config.workspace_roots.is_empty() {
                (
                    fallback_workspace_roots.clone(),
                    fallback_workspace_folders.clone(),
                )
            } else {
                (
                    config.workspace_roots.clone(),
                    config.workspace_folders.clone(),
                )
            };
            entries.push(ProjectLspStopPlanEntry {
                operation: "stop".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                language_name: config.language_name.clone(),
                server_capabilities: config.server_capabilities.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
                workspace_folders,
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
    let (fallback_workspace_roots, fallback_workspace_folders) =
        normalize_project_lsp_workspace_schema(workspace_roots.to_vec(), Vec::new());
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
            let (workspace_roots, workspace_folders) = if config.workspace_roots.is_empty() {
                (
                    fallback_workspace_roots.clone(),
                    fallback_workspace_folders.clone(),
                )
            } else {
                (
                    config.workspace_roots.clone(),
                    config.workspace_folders.clone(),
                )
            };
            entries.push(ProjectLspRestartPlanEntry {
                operation: "restart".to_string(),
                tab_id: document.tab_id,
                active_view_index: document.active_view_index,
                document_uri: document_uri.clone(),
                language_id: language_id.clone(),
                language_name: config.language_name.clone(),
                server_capabilities: config.server_capabilities.clone(),
                server_key: config.key.clone(),
                command: config.command.clone(),
                args: config.args.clone(),
                workspace_roots,
                workspace_folders,
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
    let language_name = normalize_project_lsp_language_name(&config.language_name, &language_id);
    let server_capabilities =
        normalize_project_lsp_server_capabilities(config.server_capabilities)?;
    let key = normalize_project_lsp_server_key(&config.key, &language_id, &command)?;
    let args = config
        .args
        .into_iter()
        .map(|arg| arg.trim().to_string())
        .filter(|arg| !arg.is_empty())
        .collect();
    let (workspace_roots, workspace_folders) =
        normalize_project_lsp_workspace_schema(config.workspace_roots, config.workspace_folders);

    Ok(ProjectLspServerConfig {
        key,
        command,
        args,
        language_id,
        language_name,
        server_capabilities,
        workspace_roots,
        workspace_folders,
        auto_start: config.auto_start,
    })
}

fn normalize_non_empty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn normalize_project_lsp_language_name(
    language_name: &str,
    language_id: &str,
) -> String {
    normalize_non_empty(Some(language_name)).unwrap_or_else(|| language_id.to_string())
}

pub(crate) fn default_project_lsp_server_capabilities() -> serde_json::Value {
    serde_json::Value::Object(Default::default())
}

pub(crate) fn normalize_project_lsp_server_capabilities(
    capabilities: serde_json::Value,
) -> Result<serde_json::Value, UiError> {
    match capabilities {
        serde_json::Value::Null => Ok(default_project_lsp_server_capabilities()),
        serde_json::Value::Object(_) => Ok(capabilities),
        _ => Err(UiError::Processor(
            "project LSP server capabilities must be a JSON object".to_string(),
        )),
    }
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

pub(crate) fn normalize_project_lsp_workspace_schema(
    roots: Vec<String>,
    folders: Vec<ProjectLspWorkspaceFolder>,
) -> (Vec<String>, Vec<ProjectLspWorkspaceFolder>) {
    let mut root_set = BTreeMap::new();
    let mut folders_by_uri = BTreeMap::new();

    for root in roots {
        if let Some(uri) = normalize_non_empty(Some(root.as_str())) {
            root_set.insert(uri, ());
        }
    }

    for folder in folders {
        let Some(uri) = normalize_non_empty(Some(folder.uri.as_str())) else {
            continue;
        };
        let name = normalize_non_empty(Some(folder.name.as_str()))
            .unwrap_or_else(|| project_lsp_workspace_folder_name(&uri));
        let root_alias = folder
            .root_alias
            .as_deref()
            .and_then(|alias| normalize_non_empty(Some(alias)));
        root_set.insert(uri.clone(), ());
        folders_by_uri.insert(
            uri.clone(),
            ProjectLspWorkspaceFolder {
                uri,
                name,
                root_alias,
            },
        );
    }

    let workspace_roots = root_set.into_keys().collect::<Vec<_>>();
    let workspace_folders = workspace_roots
        .iter()
        .map(|uri| {
            folders_by_uri
                .remove(uri)
                .unwrap_or_else(|| project_lsp_workspace_folder_from_uri(uri))
        })
        .collect::<Vec<_>>();

    (workspace_roots, workspace_folders)
}

fn project_lsp_workspace_folder_from_uri(uri: &str) -> ProjectLspWorkspaceFolder {
    ProjectLspWorkspaceFolder {
        uri: uri.to_string(),
        name: project_lsp_workspace_folder_name(uri),
        root_alias: None,
    }
}

fn project_lsp_workspace_folder_name(uri: &str) -> String {
    let trimmed = uri.trim_end_matches('/');
    trimmed
        .rsplit('/')
        .find(|part| !part.is_empty())
        .unwrap_or(trimmed)
        .to_string()
}

fn first_non_empty<'a>(values: impl IntoIterator<Item = &'a str>) -> Option<&'a str> {
    values
        .into_iter()
        .map(str::trim)
        .find(|value| !value.is_empty())
}
