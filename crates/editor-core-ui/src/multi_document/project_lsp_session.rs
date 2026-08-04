use crate::UiError;

pub(crate) const PROJECT_LSP_SESSION_SCOPE_WORKSPACE: &str = "workspace";
pub(crate) const PROJECT_LSP_SESSION_SCOPE_DOCUMENT: &str = "document";

const PROJECT_LSP_MERGE_SERVER_WORKSPACE_ROOTS: &str = "server_workspace_roots";
const PROJECT_LSP_MERGE_DOCUMENT: &str = "document";
const PROJECT_LSP_SHUTDOWN_LAST_DOCUMENT: &str = "last_document";
const PROJECT_LSP_SHUTDOWN_DOCUMENT_CLOSE: &str = "document_close";

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspSessionPolicy {
    #[serde(default)]
    pub scope: String,
    #[serde(default)]
    pub merge_strategy: String,
    #[serde(default)]
    pub deduplicate: bool,
    #[serde(default)]
    pub shutdown_policy: String,
}

impl Default for ProjectLspSessionPolicy {
    fn default() -> Self {
        default_project_lsp_session_policy()
    }
}

pub(crate) fn default_project_lsp_session_policy() -> ProjectLspSessionPolicy {
    ProjectLspSessionPolicy {
        scope: PROJECT_LSP_SESSION_SCOPE_WORKSPACE.to_string(),
        merge_strategy: PROJECT_LSP_MERGE_SERVER_WORKSPACE_ROOTS.to_string(),
        deduplicate: true,
        shutdown_policy: PROJECT_LSP_SHUTDOWN_LAST_DOCUMENT.to_string(),
    }
}

pub(crate) fn default_project_lsp_document_session_policy() -> ProjectLspSessionPolicy {
    ProjectLspSessionPolicy {
        scope: PROJECT_LSP_SESSION_SCOPE_DOCUMENT.to_string(),
        merge_strategy: PROJECT_LSP_MERGE_DOCUMENT.to_string(),
        deduplicate: false,
        shutdown_policy: PROJECT_LSP_SHUTDOWN_DOCUMENT_CLOSE.to_string(),
    }
}

pub(crate) fn normalize_project_lsp_session_policy(
    policy: ProjectLspSessionPolicy,
    shared_session: bool,
) -> Result<ProjectLspSessionPolicy, UiError> {
    let scope = normalize_scope(&policy.scope);
    if shared_session == false {
        return match scope.as_deref() {
            Some(PROJECT_LSP_SESSION_SCOPE_DOCUMENT)
            | Some(PROJECT_LSP_SESSION_SCOPE_WORKSPACE)
            | None => Ok(default_project_lsp_document_session_policy()),
            Some(_) => Err(invalid_project_lsp_session_scope()),
        };
    }

    match scope.as_deref() {
        Some(PROJECT_LSP_SESSION_SCOPE_DOCUMENT) => {
            Ok(default_project_lsp_document_session_policy())
        }
        Some(PROJECT_LSP_SESSION_SCOPE_WORKSPACE) | None => {
            Ok(default_project_lsp_session_policy())
        }
        Some(_) => Err(invalid_project_lsp_session_scope()),
    }
}

pub(crate) fn project_lsp_session_policy_is_shared(policy: &ProjectLspSessionPolicy) -> bool {
    policy.scope == PROJECT_LSP_SESSION_SCOPE_WORKSPACE
}

pub(crate) fn project_lsp_session_key(
    policy: &ProjectLspSessionPolicy,
    server_key: &str,
    document_uri: &str,
    workspace_roots: &[String],
) -> String {
    let server = normalize_key_part(server_key).unwrap_or_default();
    if policy.scope == PROJECT_LSP_SESSION_SCOPE_DOCUMENT {
        let document = normalize_key_part(document_uri).unwrap_or_default();
        return format!("document:{server}:{document}");
    }

    let roots = workspace_roots
        .iter()
        .filter_map(|root| normalize_key_part(root))
        .collect::<Vec<_>>()
        .join("|");
    format!("workspace:{server}:{roots}")
}

pub(crate) fn normalize_project_lsp_session_key(
    raw_key: &str,
    policy: &ProjectLspSessionPolicy,
    server_key: &str,
    document_uri: &str,
    workspace_roots: &[String],
) -> String {
    normalize_key_part(raw_key).unwrap_or_else(|| {
        project_lsp_session_key(policy, server_key, document_uri, workspace_roots)
    })
}

fn normalize_scope(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    Some(value.to_ascii_lowercase())
}

fn normalize_key_part(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    Some(value.to_string())
}

fn invalid_project_lsp_session_scope() -> UiError {
    UiError::Processor("project LSP session policy scope must be workspace or document".to_string())
}
