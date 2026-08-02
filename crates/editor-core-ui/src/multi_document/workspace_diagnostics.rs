use crate::UiError;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;

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
}

impl WorkspaceDiagnosticsStore {
    /// Remove all remembered diagnostic reports and previous-result ids.
    pub fn clear(&mut self) {
        self.documents_by_uri.clear();
        self.document_order.clear();
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
        Ok(self.snapshot())
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
