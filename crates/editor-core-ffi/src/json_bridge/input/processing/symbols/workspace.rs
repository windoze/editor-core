use super::super::*;
use super::FfiSymbolKind;

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
