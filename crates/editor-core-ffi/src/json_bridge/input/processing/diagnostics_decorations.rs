use super::*;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiIntervalInput {
    start: usize,
    end: usize,
    style_id: u32,
}

impl From<FfiIntervalInput> for Interval {
    fn from(value: FfiIntervalInput) -> Self {
        Interval::new(value.start, value.end, value.style_id)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiFoldRegionInput {
    start_line: usize,
    end_line: usize,
    #[serde(default)]
    is_collapsed: bool,
    #[serde(default = "default_fold_placeholder")]
    placeholder: String,
}

pub(crate) fn default_fold_placeholder() -> String {
    "[...]".to_string()
}

impl From<FfiFoldRegionInput> for FoldRegion {
    fn from(value: FfiFoldRegionInput) -> Self {
        FoldRegion {
            start_line: value.start_line,
            end_line: value.end_line,
            is_collapsed: value.is_collapsed,
            placeholder: value.placeholder,
        }
    }
}

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

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiDecorationPlacement {
    Before,
    After,
    AboveLine,
}

impl From<FfiDecorationPlacement> for DecorationPlacement {
    fn from(value: FfiDecorationPlacement) -> Self {
        match value {
            FfiDecorationPlacement::Before => DecorationPlacement::Before,
            FfiDecorationPlacement::After => DecorationPlacement::After,
            FfiDecorationPlacement::AboveLine => DecorationPlacement::AboveLine,
        }
    }
}

pub(crate) fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub(crate) enum FfiDecorationKind {
    InlayHint,
    CodeLens,
    DocumentLink,
    Highlight,
    Custom(u32),
}

impl From<FfiDecorationKind> for DecorationKind {
    fn from(value: FfiDecorationKind) -> Self {
        match value {
            FfiDecorationKind::InlayHint => DecorationKind::InlayHint,
            FfiDecorationKind::CodeLens => DecorationKind::CodeLens,
            FfiDecorationKind::DocumentLink => DecorationKind::DocumentLink,
            FfiDecorationKind::Highlight => DecorationKind::Highlight,
            FfiDecorationKind::Custom(v) => DecorationKind::Custom(v),
        }
    }
}

pub(crate) fn decoration_kind_to_json(value: DecorationKind) -> Value {
    match value {
        DecorationKind::InlayHint => json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => json!({ "kind": "document_link" }),
        DecorationKind::Highlight => json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDecorationInput {
    range: FfiOffsetRange,
    placement: FfiDecorationPlacement,
    kind: FfiDecorationKind,
    text: Option<String>,
    #[serde(default)]
    styles: Vec<u32>,
    tooltip: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDecorationInput> for Decoration {
    fn from(value: FfiDecorationInput) -> Self {
        Decoration {
            range: DecorationRange::new(value.range.start, value.range.end),
            placement: value.placement.into(),
            kind: value.kind.into(),
            text: value.text,
            styles: value.styles,
            tooltip: value.tooltip,
            data_json: value.data_json,
        }
    }
}
