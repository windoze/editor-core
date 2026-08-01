use super::super::FfiOffsetRange;
use crate::*;
use serde::Deserialize;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiDiagnosticSeverity {
    Error,
    Warning,
    Information,
    Hint,
}

impl From<FfiDiagnosticSeverity> for DiagnosticSeverity {
    fn from(value: FfiDiagnosticSeverity) -> Self {
        match value {
            FfiDiagnosticSeverity::Error => DiagnosticSeverity::Error,
            FfiDiagnosticSeverity::Warning => DiagnosticSeverity::Warning,
            FfiDiagnosticSeverity::Information => DiagnosticSeverity::Information,
            FfiDiagnosticSeverity::Hint => DiagnosticSeverity::Hint,
        }
    }
}

pub(crate) fn diagnostic_severity_to_str(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Information => "information",
        DiagnosticSeverity::Hint => "hint",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDiagnosticInput {
    range: FfiOffsetRange,
    severity: Option<FfiDiagnosticSeverity>,
    code: Option<String>,
    source: Option<String>,
    message: String,
    related_information_json: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDiagnosticInput> for Diagnostic {
    fn from(value: FfiDiagnosticInput) -> Self {
        Diagnostic {
            range: DiagnosticRange::new(value.range.start, value.range.end),
            severity: value.severity.map(Into::into),
            code: value.code,
            source: value.source,
            message: value.message,
            related_information_json: value.related_information_json,
            data_json: value.data_json,
        }
    }
}
