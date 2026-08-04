use super::super::FfiOffsetRange;
use crate::*;
use serde::Deserialize;
use serde_json::{Value, json};

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
