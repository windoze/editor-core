use super::*;

pub(crate) fn value_offset_range(start: usize, end: usize) -> serde_json::Value {
    serde_json::json!({ "start": start, "end": end })
}

pub(crate) fn lsp_signature_help_capability_json(
    capabilities: &serde_json::Value,
) -> serde_json::Value {
    let provider = capabilities.get("signatureHelpProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let retrigger_characters =
        lsp_string_array(provider.and_then(|p| p.get("retriggerCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "retrigger_characters": retrigger_characters,
    })
}

pub(crate) fn lsp_completion_capability_json(
    capabilities: &serde_json::Value,
) -> serde_json::Value {
    let provider = capabilities.get("completionProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let all_commit_characters =
        lsp_string_array(provider.and_then(|p| p.get("allCommitCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "all_commit_characters": all_commit_characters,
    })
}

pub(crate) fn lsp_string_array(value: Option<&serde_json::Value>) -> Vec<String> {
    value
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(ToString::to_string))
                .collect()
        })
        .unwrap_or_default()
}

pub(crate) fn parse_lsp_formatting_options(
    formatting_options_json: &str,
) -> Result<serde_json::Value, UiError> {
    if formatting_options_json.trim().is_empty() {
        Ok(serde_json::json!({
            "tabSize": 4,
            "insertSpaces": true,
        }))
    } else {
        serde_json::from_str(formatting_options_json).map_err(|e| UiError::Processor(e.to_string()))
    }
}

pub(crate) fn parse_lsp_position_list_json(
    positions_json: &str,
) -> Result<Vec<(usize, usize)>, UiError> {
    let value: serde_json::Value =
        serde_json::from_str(positions_json).map_err(|e| UiError::Processor(e.to_string()))?;
    let positions = value.as_array().ok_or_else(|| {
        UiError::Processor("selection range positions must be an array".to_string())
    })?;

    positions
        .iter()
        .map(|position| {
            let line = position
                .get("line")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing line".to_string())
                })?;
            let column = position
                .get("column")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing column".to_string())
                })?;
            let line = usize::try_from(line)
                .map_err(|_| UiError::Processor("selection range line is too large".to_string()))?;
            let column = usize::try_from(column).map_err(|_| {
                UiError::Processor("selection range column is too large".to_string())
            })?;
            Ok((line, column))
        })
        .collect()
}

pub(crate) fn parse_lsp_json_array(
    value_json: &str,
    name: &str,
) -> Result<Vec<serde_json::Value>, UiError> {
    if value_json.trim().is_empty() {
        return Ok(Vec::new());
    }

    let value: serde_json::Value =
        serde_json::from_str(value_json).map_err(|e| UiError::Processor(e.to_string()))?;
    value
        .as_array()
        .cloned()
        .ok_or_else(|| UiError::Processor(format!("{name} must be a JSON array")))
}

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

pub(crate) fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

pub(crate) fn decoration_kind_to_json(value: DecorationKind) -> serde_json::Value {
    match value {
        DecorationKind::InlayHint => serde_json::json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => serde_json::json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => serde_json::json!({ "kind": "document_link" }),
        DecorationKind::Highlight => serde_json::json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

pub(crate) fn value_decoration(decoration: &editor_core::Decoration) -> serde_json::Value {
    serde_json::json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

pub(crate) fn value_fold_region(region: &FoldRegion) -> serde_json::Value {
    serde_json::json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

pub(crate) fn value_interval(interval: &Interval) -> serde_json::Value {
    serde_json::json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}

pub(crate) fn symbol_kind_to_json(value: SymbolKind) -> serde_json::Value {
    match value {
        SymbolKind::File => serde_json::json!({ "kind": "file" }),
        SymbolKind::Module => serde_json::json!({ "kind": "module" }),
        SymbolKind::Namespace => serde_json::json!({ "kind": "namespace" }),
        SymbolKind::Package => serde_json::json!({ "kind": "package" }),
        SymbolKind::Class => serde_json::json!({ "kind": "class" }),
        SymbolKind::Method => serde_json::json!({ "kind": "method" }),
        SymbolKind::Property => serde_json::json!({ "kind": "property" }),
        SymbolKind::Field => serde_json::json!({ "kind": "field" }),
        SymbolKind::Constructor => serde_json::json!({ "kind": "constructor" }),
        SymbolKind::Enum => serde_json::json!({ "kind": "enum" }),
        SymbolKind::Interface => serde_json::json!({ "kind": "interface" }),
        SymbolKind::Function => serde_json::json!({ "kind": "function" }),
        SymbolKind::Variable => serde_json::json!({ "kind": "variable" }),
        SymbolKind::Constant => serde_json::json!({ "kind": "constant" }),
        SymbolKind::String => serde_json::json!({ "kind": "string" }),
        SymbolKind::Number => serde_json::json!({ "kind": "number" }),
        SymbolKind::Boolean => serde_json::json!({ "kind": "boolean" }),
        SymbolKind::Array => serde_json::json!({ "kind": "array" }),
        SymbolKind::Object => serde_json::json!({ "kind": "object" }),
        SymbolKind::Key => serde_json::json!({ "kind": "key" }),
        SymbolKind::Null => serde_json::json!({ "kind": "null" }),
        SymbolKind::EnumMember => serde_json::json!({ "kind": "enum_member" }),
        SymbolKind::Struct => serde_json::json!({ "kind": "struct" }),
        SymbolKind::Event => serde_json::json!({ "kind": "event" }),
        SymbolKind::Operator => serde_json::json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => serde_json::json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

pub(crate) fn value_document_symbol(symbol: &DocumentSymbol) -> serde_json::Value {
    serde_json::json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
}
