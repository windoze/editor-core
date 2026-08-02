use crate::UiError;
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, VecDeque};

const WORKSPACE_DIAGNOSTIC_EVENT_LIMIT: usize = 128;

/// LSP target location for a workspace diagnostic.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticTarget {
    pub uri: String,
    pub line: u32,
    pub utf16_character: u32,
}

/// Normalized diagnostic entry owned by the multi-document/project UI model.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnostic {
    pub target: WorkspaceDiagnosticTarget,
    pub end_line: u32,
    pub end_utf16_character: u32,
    pub severity: Option<u32>,
    pub severity_label: Option<&'static str>,
    pub code: Option<String>,
    pub source: Option<String>,
    pub message: String,
    pub result_id: Option<String>,
}

/// Normalized per-document workspace diagnostic report.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticDocumentReport {
    pub uri: String,
    pub kind: String,
    pub result_id: Option<String>,
    pub diagnostics: Vec<WorkspaceDiagnostic>,
}

/// Snapshot of the current workspace diagnostic state.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticsSnapshot {
    pub documents: Vec<WorkspaceDiagnosticDocumentReport>,
    pub diagnostics: Vec<WorkspaceDiagnostic>,
}

/// Lightweight project-level diagnostic marker projection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticMarker {
    pub uri: String,
    pub line: u32,
    pub utf16_character: u32,
    pub severity: Option<u32>,
    pub severity_label: Option<&'static str>,
}

/// Snapshot of project-level diagnostic markers.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticMarkersSnapshot {
    pub markers: Vec<WorkspaceDiagnosticMarker>,
}

/// Event emitted by the core-owned workspace diagnostics store.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticsEvent {
    pub sequence: u64,
    pub family: &'static str,
    pub title: String,
    pub operation: &'static str,
    pub document_count: usize,
    pub diagnostic_count: usize,
    pub marker_count: usize,
}

/// Cursor-based event snapshot for core-owned workspace diagnostics updates.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct WorkspaceDiagnosticsEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<WorkspaceDiagnosticsEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
struct PreviousResultId<'a> {
    uri: &'a str,
    value: &'a str,
}

/// Incremental workspace diagnostic store for the multi-document/project UI model.
#[derive(Debug, Clone, Default)]
pub struct WorkspaceDiagnosticsStore {
    documents_by_uri: BTreeMap<String, WorkspaceDiagnosticDocumentReport>,
    document_order: Vec<String>,
    next_event_sequence: u64,
    events: VecDeque<WorkspaceDiagnosticsEvent>,
}

impl WorkspaceDiagnosticsStore {
    /// Remove all remembered diagnostic reports and previous-result ids.
    pub fn clear(&mut self) {
        self.documents_by_uri.clear();
        self.document_order.clear();
        self.record_event("clear", self.snapshot());
    }

    /// Return a stable snapshot of remembered reports and their flattened diagnostics.
    pub fn snapshot(&self) -> WorkspaceDiagnosticsSnapshot {
        let documents: Vec<_> = self
            .document_order
            .iter()
            .filter_map(|uri| self.documents_by_uri.get(uri).cloned())
            .collect();
        let diagnostics = documents
            .iter()
            .flat_map(|report| report.diagnostics.iter().cloned())
            .collect();
        WorkspaceDiagnosticsSnapshot {
            documents,
            diagnostics,
        }
    }

    /// Return the snapshot as JSON.
    pub fn snapshot_json(&self) -> Result<String, UiError> {
        serde_json::to_string(&self.snapshot()).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace diagnostics snapshot: {err}"
            ))
        })
    }

    /// Return marker projections for all remembered workspace diagnostics.
    pub fn marker_snapshot(&self) -> WorkspaceDiagnosticMarkersSnapshot {
        let markers = self
            .snapshot()
            .diagnostics
            .into_iter()
            .map(|diagnostic| WorkspaceDiagnosticMarker {
                uri: diagnostic.target.uri,
                line: diagnostic.target.line,
                utf16_character: diagnostic.target.utf16_character,
                severity: diagnostic.severity,
                severity_label: diagnostic.severity_label,
            })
            .collect();
        WorkspaceDiagnosticMarkersSnapshot { markers }
    }

    /// Return marker projections as JSON.
    pub fn marker_snapshot_json(&self) -> Result<String, UiError> {
        serde_json::to_string(&self.marker_snapshot()).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace diagnostic markers: {err}"
            ))
        })
    }

    /// Return previous-result ids in the shape expected by `workspace/diagnostic`.
    pub fn previous_result_ids_json(&self) -> Result<String, UiError> {
        let snapshot = self.snapshot();
        let values: Vec<_> = snapshot
            .documents
            .iter()
            .filter_map(|report| {
                Some(PreviousResultId {
                    uri: report.uri.as_str(),
                    value: report.result_id.as_deref()?,
                })
            })
            .collect();
        serde_json::to_string(&values).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace diagnostics previousResultIds: {err}"
            ))
        })
    }

    /// Return latest workspace diagnostics event sequence.
    pub fn latest_event_sequence(&self) -> u64 {
        self.next_event_sequence
    }

    /// Return workspace diagnostics events newer than `after_sequence`.
    pub fn events_after(&self, after_sequence: u64) -> WorkspaceDiagnosticsEventsSnapshot {
        WorkspaceDiagnosticsEventsSnapshot {
            latest_sequence: self.latest_event_sequence(),
            events: self
                .events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }

    /// Return workspace diagnostics events newer than `after_sequence` as JSON.
    pub fn events_after_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.events_after(after_sequence)).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace diagnostics events: {err}"
            ))
        })
    }

    /// Parse and merge an LSP `workspace/diagnostic` result JSON payload.
    pub fn apply_lsp_result_json(
        &mut self,
        json: &str,
    ) -> Result<WorkspaceDiagnosticsSnapshot, UiError> {
        let root: Value = serde_json::from_str(json).map_err(|err| {
            UiError::Processor(format!("failed to parse workspace diagnostics JSON: {err}"))
        })?;
        let mut reports = Vec::new();
        append_document_reports(&root, None, &mut reports);
        self.apply_reports(reports);
        let snapshot = self.snapshot();
        self.record_event("apply", snapshot.clone());
        Ok(snapshot)
    }

    fn apply_reports(&mut self, reports: Vec<WorkspaceDiagnosticDocumentReport>) {
        for report in reports {
            self.remember(report.uri.as_str());
            if report.kind.eq_ignore_ascii_case("unchanged")
                && let Some(existing) = self.documents_by_uri.get(report.uri.as_str())
            {
                let merged = WorkspaceDiagnosticDocumentReport {
                    uri: existing.uri.clone(),
                    kind: report.kind,
                    result_id: report.result_id.or_else(|| existing.result_id.clone()),
                    diagnostics: existing.diagnostics.clone(),
                };
                self.documents_by_uri.insert(report.uri.clone(), merged);
            } else {
                self.documents_by_uri.insert(report.uri.clone(), report);
            }
        }
    }

    fn remember(&mut self, uri: &str) {
        if self.documents_by_uri.contains_key(uri) || self.document_order.iter().any(|u| u == uri) {
            return;
        }
        self.document_order.push(uri.to_string());
    }

    fn record_event(&mut self, operation: &'static str, snapshot: WorkspaceDiagnosticsSnapshot) {
        self.next_event_sequence = self.next_event_sequence.saturating_add(1);
        let document_count = snapshot.documents.len();
        let diagnostic_count = snapshot.diagnostics.len();
        let marker_count = diagnostic_count;
        let title = match operation {
            "clear" => "Workspace Diagnostics: cleared".to_string(),
            _ if diagnostic_count == 1 => "Workspace Diagnostics: 1 problem".to_string(),
            _ => format!("Workspace Diagnostics: {diagnostic_count} problems"),
        };
        self.events.push_back(WorkspaceDiagnosticsEvent {
            sequence: self.next_event_sequence,
            family: "workspace_diagnostics",
            title,
            operation,
            document_count,
            diagnostic_count,
            marker_count,
        });
        while self.events.len() > WORKSPACE_DIAGNOSTIC_EVENT_LIMIT {
            self.events.pop_front();
        }
    }
}

fn append_document_reports(
    value: &Value,
    fallback_uri: Option<&str>,
    out: &mut Vec<WorkspaceDiagnosticDocumentReport>,
) {
    match value {
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_) => {}
        Value::Array(items) => {
            for item in items {
                append_document_reports(item, fallback_uri, out);
            }
        }
        Value::Object(map) => {
            if map.get("kind").is_none()
                && let Some(Value::Array(items)) = map.get("items")
            {
                for item in items {
                    append_document_reports(item, None, out);
                }
                return;
            }

            let Some(uri) = non_empty_string(map.get("uri")).or(fallback_uri) else {
                return;
            };
            let kind = non_empty_string(map.get("kind"))
                .unwrap_or("full")
                .to_string();
            let result_id = non_empty_string(map.get("resultId")).map(ToOwned::to_owned);
            let diagnostics = map
                .get("items")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|item| diagnostic_from_value(item, uri, result_id.as_deref()))
                .collect();
            out.push(WorkspaceDiagnosticDocumentReport {
                uri: uri.to_string(),
                kind,
                result_id,
                diagnostics,
            });

            if let Some(Value::Object(related)) = map.get("relatedDocuments") {
                for (related_uri, report) in related {
                    append_document_reports(report, Some(related_uri.as_str()), out);
                }
            }
        }
    }
}

fn diagnostic_from_value(
    value: &Value,
    uri: &str,
    result_id: Option<&str>,
) -> Option<WorkspaceDiagnostic> {
    let map = value.as_object()?;
    let range = map.get("range")?.as_object()?;
    let start = range.get("start")?.as_object()?;
    let end = range.get("end")?.as_object()?;
    let start_line = u32_value(start.get("line"))?;
    let start_character = u32_value(start.get("character"))?;
    let end_line = u32_value(end.get("line"))?;
    let end_character = u32_value(end.get("character"))?;
    let message = non_empty_string(map.get("message"))?.to_string();
    let severity = u32_value(map.get("severity"));

    Some(WorkspaceDiagnostic {
        target: WorkspaceDiagnosticTarget {
            uri: uri.to_string(),
            line: start_line,
            utf16_character: start_character,
        },
        end_line,
        end_utf16_character: end_character,
        severity,
        severity_label: severity_label(severity),
        code: code_string(map.get("code")),
        source: non_empty_string(map.get("source")).map(ToOwned::to_owned),
        message,
        result_id: result_id.map(ToOwned::to_owned),
    })
}

fn non_empty_string(value: Option<&Value>) -> Option<&str> {
    let s = value?.as_str()?;
    if s.trim().is_empty() { None } else { Some(s) }
}

fn u32_value(value: Option<&Value>) -> Option<u32> {
    let n = value?.as_u64()?;
    u32::try_from(n).ok()
}

fn code_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(s) if !s.trim().is_empty() => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

fn severity_label(value: Option<u32>) -> Option<&'static str> {
    match value {
        Some(1) => Some("error"),
        Some(2) => Some("warning"),
        Some(3) => Some("information"),
        Some(4) => Some("hint"),
        _ => None,
    }
}
