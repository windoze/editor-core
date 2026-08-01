use super::super::*;
use super::FfiSymbolKind;

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
