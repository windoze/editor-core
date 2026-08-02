use super::*;

pub(crate) fn diagnostic_severity_to_str(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Information => "information",
        DiagnosticSeverity::Hint => "hint",
    }
}

pub(crate) fn value_diagnostic(diagnostic: &editor_core::Diagnostic) -> serde_json::Value {
    serde_json::json!({
        "range": value_offset_range(diagnostic.range.start, diagnostic.range.end),
        "severity": diagnostic.severity.map(diagnostic_severity_to_str),
        "code": diagnostic.code,
        "source": diagnostic.source,
        "message": diagnostic.message,
        "related_information_json": diagnostic.related_information_json,
        "data_json": diagnostic.data_json
    })
}
