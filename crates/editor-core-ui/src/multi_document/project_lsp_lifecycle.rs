use super::project_lsp::{
    ProjectLspRecoveryPolicy, ProjectLspWorkspaceFolder, default_project_lsp_recovery_policy,
    default_project_lsp_server_capabilities, default_project_lsp_shared_session,
    normalize_project_lsp_language_name, normalize_project_lsp_recovery_policy,
    normalize_project_lsp_server_capabilities, normalize_project_lsp_workspace_schema,
};
use super::project_lsp_session::{
    ProjectLspSessionPolicy, default_project_lsp_session_policy, normalize_project_lsp_session_key,
    normalize_project_lsp_session_policy, project_lsp_session_policy_is_shared,
};
use crate::UiError;
use std::collections::VecDeque;

const MAX_PROJECT_LSP_LIFECYCLE_EVENTS: usize = 512;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspStartOutcome {
    pub tab_id: u64,
    #[serde(default)]
    pub active_view_index: usize,
    #[serde(default = "default_project_lsp_lifecycle_operation")]
    pub operation: String,
    #[serde(default)]
    pub document_uri: String,
    #[serde(default)]
    pub language_id: String,
    #[serde(default)]
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    #[serde(default = "default_project_lsp_shared_session")]
    pub shared_session: bool,
    #[serde(default)]
    pub session_key: String,
    #[serde(default = "default_project_lsp_session_policy")]
    pub session_policy: ProjectLspSessionPolicy,
    #[serde(default)]
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
    #[serde(default = "default_project_lsp_recovery_policy")]
    pub recovery_policy: ProjectLspRecoveryPolicy,
    #[serde(default = "default_project_lsp_lifecycle_trigger")]
    pub trigger: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempt_id: Option<u64>,
    pub status: String,
    #[serde(default)]
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspLifecycleEvent {
    pub sequence: u64,
    pub operation: String,
    pub trigger: String,
    pub status: String,
    pub tab_id: u64,
    pub active_view_index: usize,
    pub document_uri: String,
    pub language_id: String,
    pub language_name: String,
    #[serde(default = "default_project_lsp_server_capabilities")]
    pub server_capabilities: serde_json::Value,
    #[serde(default = "default_project_lsp_shared_session")]
    pub shared_session: bool,
    #[serde(default)]
    pub session_key: String,
    #[serde(default = "default_project_lsp_session_policy")]
    pub session_policy: ProjectLspSessionPolicy,
    pub server_key: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub workspace_roots: Vec<String>,
    #[serde(default)]
    pub workspace_folders: Vec<ProjectLspWorkspaceFolder>,
    #[serde(default = "default_project_lsp_recovery_policy")]
    pub recovery_policy: ProjectLspRecoveryPolicy,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempt_id: Option<u64>,
    #[serde(default)]
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProjectLspLifecycleEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<ProjectLspLifecycleEvent>,
}

#[derive(Default)]
pub(crate) struct ProjectLspLifecycleEventStore {
    next_sequence: u64,
    events: VecDeque<ProjectLspLifecycleEvent>,
}

impl ProjectLspLifecycleEventStore {
    pub(crate) fn record_start_outcome(
        &mut self,
        outcome: ProjectLspStartOutcome,
    ) -> Result<ProjectLspLifecycleEvent, UiError> {
        if self.next_sequence == 0 {
            self.next_sequence = 1;
        }

        let command = normalize_required("project LSP start outcome command", &outcome.command)?;
        let operation = normalize_project_lsp_lifecycle_operation(&outcome.operation)?;
        let status = normalize_project_lsp_lifecycle_status(&outcome.status)?;
        let (workspace_roots, workspace_folders) = normalize_project_lsp_workspace_schema(
            outcome.workspace_roots,
            outcome.workspace_folders,
        );
        let language_id = normalize_optional(&outcome.language_id).unwrap_or_default();
        let language_name =
            normalize_project_lsp_language_name(&outcome.language_name, &language_id);
        let server_capabilities =
            normalize_project_lsp_server_capabilities(outcome.server_capabilities)?;
        let server_key = normalize_optional(&outcome.server_key).unwrap_or_default();
        let document_uri = normalize_optional(&outcome.document_uri).unwrap_or_default();
        let session_policy =
            normalize_project_lsp_session_policy(outcome.session_policy, outcome.shared_session)?;
        let shared_session = project_lsp_session_policy_is_shared(&session_policy);
        let session_key = normalize_project_lsp_session_key(
            &outcome.session_key,
            &session_policy,
            &server_key,
            &document_uri,
            &workspace_roots,
        );
        let recovery_policy = normalize_project_lsp_recovery_policy(outcome.recovery_policy);
        let attempt_id = outcome
            .attempt_id
            .or_else(|| (status == "requested").then_some(self.next_sequence));
        let event = ProjectLspLifecycleEvent {
            sequence: self.next_sequence,
            operation,
            trigger: normalize_optional(&outcome.trigger)
                .unwrap_or_else(default_project_lsp_lifecycle_trigger),
            status,
            tab_id: outcome.tab_id,
            active_view_index: outcome.active_view_index,
            document_uri,
            language_id,
            language_name,
            server_capabilities,
            shared_session,
            session_key,
            session_policy,
            server_key,
            command,
            args: normalize_non_empty_vec(outcome.args),
            workspace_roots,
            workspace_folders,
            recovery_policy,
            attempt_id,
            error_message: outcome
                .error_message
                .and_then(|message| normalize_optional(&message)),
        };

        self.next_sequence = self.next_sequence.saturating_add(1);
        self.events.push_back(event.clone());
        while self.events.len() > MAX_PROJECT_LSP_LIFECYCLE_EVENTS {
            self.events.pop_front();
        }

        Ok(event)
    }

    pub(crate) fn latest_sequence(&self) -> u64 {
        self.next_sequence.saturating_sub(1)
    }

    pub(crate) fn next_attempt_id(&self) -> u64 {
        self.next_sequence.max(1)
    }

    pub(crate) fn events_after(&self, after_sequence: u64) -> ProjectLspLifecycleEventsSnapshot {
        ProjectLspLifecycleEventsSnapshot {
            latest_sequence: self.latest_sequence(),
            events: self
                .events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }

    pub(crate) fn events_after_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.events_after(after_sequence)).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode project LSP lifecycle events: {err}"
            ))
        })
    }
}

fn default_project_lsp_lifecycle_trigger() -> String {
    "auto_start".to_string()
}

fn default_project_lsp_lifecycle_operation() -> String {
    "start".to_string()
}

fn normalize_project_lsp_lifecycle_operation(operation: &str) -> Result<String, UiError> {
    let operation = normalize_required("project LSP lifecycle outcome operation", operation)?
        .to_ascii_lowercase();
    match operation.as_str() {
        "start" | "restart" | "stop" => Ok(operation),
        _ => Err(UiError::Processor(format!(
            "project LSP lifecycle outcome operation must be 'start', 'restart', or 'stop', got '{operation}'"
        ))),
    }
}

fn normalize_project_lsp_lifecycle_status(status: &str) -> Result<String, UiError> {
    let status =
        normalize_required("project LSP lifecycle outcome status", status)?.to_ascii_lowercase();
    match status.as_str() {
        "requested" | "started" | "stopped" | "failed" | "skipped" => Ok(status),
        _ => Err(UiError::Processor(format!(
            "project LSP lifecycle outcome status must be 'requested', 'started', 'stopped', 'failed', or 'skipped', got '{status}'"
        ))),
    }
}

fn normalize_required(label: &str, value: &str) -> Result<String, UiError> {
    normalize_optional(value).ok_or_else(|| UiError::Processor(format!("{label} cannot be empty")))
}

fn normalize_optional(value: &str) -> Option<String> {
    let normalized = value.trim().to_string();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized)
    }
}

fn normalize_non_empty_vec(values: Vec<String>) -> Vec<String> {
    values
        .into_iter()
        .filter_map(|value| normalize_optional(&value))
        .collect()
}
