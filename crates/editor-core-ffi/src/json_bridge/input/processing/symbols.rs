use super::*;

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
