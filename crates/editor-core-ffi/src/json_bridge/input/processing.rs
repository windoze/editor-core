use super::super::*;

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

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub(crate) enum FfiSymbolKind {
    File,
    Module,
    Namespace,
    Package,
    Class,
    Method,
    Property,
    Field,
    Constructor,
    Enum,
    Interface,
    Function,
    Variable,
    Constant,
    String,
    Number,
    Boolean,
    Array,
    Object,
    Key,
    Null,
    EnumMember,
    Struct,
    Event,
    Operator,
    TypeParameter,
    Custom(u32),
}

impl From<FfiSymbolKind> for SymbolKind {
    fn from(value: FfiSymbolKind) -> Self {
        match value {
            FfiSymbolKind::File => SymbolKind::File,
            FfiSymbolKind::Module => SymbolKind::Module,
            FfiSymbolKind::Namespace => SymbolKind::Namespace,
            FfiSymbolKind::Package => SymbolKind::Package,
            FfiSymbolKind::Class => SymbolKind::Class,
            FfiSymbolKind::Method => SymbolKind::Method,
            FfiSymbolKind::Property => SymbolKind::Property,
            FfiSymbolKind::Field => SymbolKind::Field,
            FfiSymbolKind::Constructor => SymbolKind::Constructor,
            FfiSymbolKind::Enum => SymbolKind::Enum,
            FfiSymbolKind::Interface => SymbolKind::Interface,
            FfiSymbolKind::Function => SymbolKind::Function,
            FfiSymbolKind::Variable => SymbolKind::Variable,
            FfiSymbolKind::Constant => SymbolKind::Constant,
            FfiSymbolKind::String => SymbolKind::String,
            FfiSymbolKind::Number => SymbolKind::Number,
            FfiSymbolKind::Boolean => SymbolKind::Boolean,
            FfiSymbolKind::Array => SymbolKind::Array,
            FfiSymbolKind::Object => SymbolKind::Object,
            FfiSymbolKind::Key => SymbolKind::Key,
            FfiSymbolKind::Null => SymbolKind::Null,
            FfiSymbolKind::EnumMember => SymbolKind::EnumMember,
            FfiSymbolKind::Struct => SymbolKind::Struct,
            FfiSymbolKind::Event => SymbolKind::Event,
            FfiSymbolKind::Operator => SymbolKind::Operator,
            FfiSymbolKind::TypeParameter => SymbolKind::TypeParameter,
            FfiSymbolKind::Custom(v) => SymbolKind::Custom(v),
        }
    }
}

pub(crate) fn symbol_kind_to_json(value: SymbolKind) -> Value {
    match value {
        SymbolKind::File => json!({ "kind": "file" }),
        SymbolKind::Module => json!({ "kind": "module" }),
        SymbolKind::Namespace => json!({ "kind": "namespace" }),
        SymbolKind::Package => json!({ "kind": "package" }),
        SymbolKind::Class => json!({ "kind": "class" }),
        SymbolKind::Method => json!({ "kind": "method" }),
        SymbolKind::Property => json!({ "kind": "property" }),
        SymbolKind::Field => json!({ "kind": "field" }),
        SymbolKind::Constructor => json!({ "kind": "constructor" }),
        SymbolKind::Enum => json!({ "kind": "enum" }),
        SymbolKind::Interface => json!({ "kind": "interface" }),
        SymbolKind::Function => json!({ "kind": "function" }),
        SymbolKind::Variable => json!({ "kind": "variable" }),
        SymbolKind::Constant => json!({ "kind": "constant" }),
        SymbolKind::String => json!({ "kind": "string" }),
        SymbolKind::Number => json!({ "kind": "number" }),
        SymbolKind::Boolean => json!({ "kind": "boolean" }),
        SymbolKind::Array => json!({ "kind": "array" }),
        SymbolKind::Object => json!({ "kind": "object" }),
        SymbolKind::Key => json!({ "kind": "key" }),
        SymbolKind::Null => json!({ "kind": "null" }),
        SymbolKind::EnumMember => json!({ "kind": "enum_member" }),
        SymbolKind::Struct => json!({ "kind": "struct" }),
        SymbolKind::Event => json!({ "kind": "event" }),
        SymbolKind::Operator => json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiOffsetRange {
    start: usize,
    end: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiUtf16Position {
    line: u32,
    character: u32,
}

impl From<FfiUtf16Position> for Utf16Position {
    fn from(value: FfiUtf16Position) -> Self {
        Utf16Position::new(value.line, value.character)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiUtf16Range {
    start: FfiUtf16Position,
    end: FfiUtf16Position,
}

impl From<FfiUtf16Range> for Utf16Range {
    fn from(value: FfiUtf16Range) -> Self {
        Utf16Range::new(value.start.into(), value.end.into())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiSymbolLocation {
    uri: String,
    range: FfiUtf16Range,
}

impl From<FfiSymbolLocation> for SymbolLocation {
    fn from(value: FfiSymbolLocation) -> Self {
        SymbolLocation {
            uri: value.uri,
            range: value.range.into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDocumentSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    range: FfiOffsetRange,
    selection_range: FfiOffsetRange,
    #[serde(default)]
    children: Vec<FfiDocumentSymbolInput>,
    data_json: Option<String>,
}

impl From<FfiDocumentSymbolInput> for DocumentSymbol {
    fn from(value: FfiDocumentSymbolInput) -> Self {
        DocumentSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            range: SymbolRange::new(value.range.start, value.range.end),
            selection_range: SymbolRange::new(
                value.selection_range.start,
                value.selection_range.end,
            ),
            children: value.children.into_iter().map(Into::into).collect(),
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiWorkspaceSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    location: FfiSymbolLocation,
    container_name: Option<String>,
    data_json: Option<String>,
}

impl From<FfiWorkspaceSymbolInput> for WorkspaceSymbol {
    fn from(value: FfiWorkspaceSymbolInput) -> Self {
        WorkspaceSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            location: value.location.into(),
            container_name: value.container_name,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiProcessingEditInput {
    ReplaceStyleLayer {
        layer: u32,
        intervals: Vec<FfiIntervalInput>,
    },
    ClearStyleLayer {
        layer: u32,
    },
    ReplaceFoldingRegions {
        regions: Vec<FfiFoldRegionInput>,
        #[serde(default)]
        preserve_collapsed: bool,
    },
    ClearFoldingRegions,
    ReplaceDiagnostics {
        diagnostics: Vec<FfiDiagnosticInput>,
    },
    ClearDiagnostics,
    ReplaceDecorations {
        layer: u32,
        decorations: Vec<FfiDecorationInput>,
    },
    ClearDecorations {
        layer: u32,
    },
    ReplaceDocumentSymbols {
        symbols: Vec<FfiDocumentSymbolInput>,
    },
    ClearDocumentSymbols,
}

impl FfiProcessingEditInput {
    fn into_core(self) -> ProcessingEdit {
        match self {
            Self::ReplaceStyleLayer { layer, intervals } => ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::new(layer),
                intervals: intervals.into_iter().map(Into::into).collect(),
            },
            Self::ClearStyleLayer { layer } => ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::new(layer),
            },
            Self::ReplaceFoldingRegions {
                regions,
                preserve_collapsed,
            } => ProcessingEdit::ReplaceFoldingRegions {
                regions: regions.into_iter().map(Into::into).collect(),
                preserve_collapsed,
            },
            Self::ClearFoldingRegions => ProcessingEdit::ClearFoldingRegions,
            Self::ReplaceDiagnostics { diagnostics } => ProcessingEdit::ReplaceDiagnostics {
                diagnostics: diagnostics.into_iter().map(Into::into).collect(),
            },
            Self::ClearDiagnostics => ProcessingEdit::ClearDiagnostics,
            Self::ReplaceDecorations { layer, decorations } => ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::new(layer),
                decorations: decorations.into_iter().map(Into::into).collect(),
            },
            Self::ClearDecorations { layer } => ProcessingEdit::ClearDecorations {
                layer: DecorationLayerId::new(layer),
            },
            Self::ReplaceDocumentSymbols { symbols } => ProcessingEdit::ReplaceDocumentSymbols {
                symbols: DocumentOutline::new(symbols.into_iter().map(Into::into).collect()),
            },
            Self::ClearDocumentSymbols => ProcessingEdit::ClearDocumentSymbols,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub(crate) enum FfiProcessingEditsInput {
    One(FfiProcessingEditInput),
    Many(Vec<FfiProcessingEditInput>),
}

impl FfiProcessingEditsInput {
    pub(crate) fn into_core(self) -> Vec<ProcessingEdit> {
        match self {
            Self::One(edit) => vec![edit.into_core()],
            Self::Many(edits) => edits
                .into_iter()
                .map(FfiProcessingEditInput::into_core)
                .collect(),
        }
    }
}
