//! Helpers for parsing LSP signature help payloads (`textDocument/signatureHelp`).
//!
//! This module intentionally stays dependency-light and operates on `serde_json::Value`.

use super::lsp_hover::{LspMarkupContent, LspMarkupKind};
use serde_json::Value;

fn u64_to_u32_saturating(value: u64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

/// LSP `ParameterInformation.label`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LspParameterLabel {
    /// A simple string label.
    String(String),
    /// A (start,end) pair of UTF-16 offsets within the signature label.
    Offsets(u32, u32),
}

/// LSP `ParameterInformation`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspParameterInformation {
    /// Parameter label.
    pub label: Option<LspParameterLabel>,
    /// Optional documentation (`MarkupContent` only; other shapes are ignored).
    pub documentation: Option<LspMarkupContent>,
}

/// LSP `SignatureInformation`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspSignatureInformation {
    /// Signature label (human-facing).
    pub label: String,
    /// Optional documentation (`MarkupContent` only; other shapes are ignored).
    pub documentation: Option<LspMarkupContent>,
    /// Optional parameter list.
    pub parameters: Vec<LspParameterInformation>,
}

/// LSP `SignatureHelp`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspSignatureHelp {
    /// Signatures.
    pub signatures: Vec<LspSignatureInformation>,
    /// Active signature index.
    pub active_signature: Option<u32>,
    /// Active parameter index.
    pub active_parameter: Option<u32>,
}

fn markup_kind_from_str(s: &str) -> Option<LspMarkupKind> {
    match s {
        "plaintext" => Some(LspMarkupKind::PlainText),
        "markdown" => Some(LspMarkupKind::Markdown),
        _ => None,
    }
}

fn markup_content_from_value(v: &Value) -> Option<LspMarkupContent> {
    let kind = v
        .get("kind")
        .and_then(Value::as_str)
        .and_then(markup_kind_from_str)?;
    let value = v.get("value").and_then(Value::as_str)?.to_string();
    Some(LspMarkupContent { kind, value })
}

fn documentation_from_value(v: &Value) -> Option<LspMarkupContent> {
    // LSP docs can be MarkupContent | string in some servers. We accept MarkupContent only here.
    if v.is_object() {
        return markup_content_from_value(v);
    }
    None
}

fn parameter_label_from_value(v: &Value) -> Option<LspParameterLabel> {
    if let Some(s) = v.as_str() {
        return Some(LspParameterLabel::String(s.to_string()));
    }
    if let Some(arr) = v.as_array()
        && arr.len() == 2
        && let (Some(a), Some(b)) = (arr[0].as_u64(), arr[1].as_u64())
    {
        return Some(LspParameterLabel::Offsets(
            u64_to_u32_saturating(a),
            u64_to_u32_saturating(b),
        ));
    }
    None
}

fn parameter_from_value(v: &Value) -> Option<LspParameterInformation> {
    let label = v.get("label").and_then(parameter_label_from_value);
    let documentation = v.get("documentation").and_then(documentation_from_value);
    Some(LspParameterInformation {
        label,
        documentation,
    })
}

fn signature_from_value(v: &Value) -> Option<LspSignatureInformation> {
    let label = v.get("label").and_then(Value::as_str)?.to_string();
    let documentation = v.get("documentation").and_then(documentation_from_value);
    let parameters = v
        .get("parameters")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(parameter_from_value)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Some(LspSignatureInformation {
        label,
        documentation,
        parameters,
    })
}

/// Parse a `SignatureHelp | null` JSON value into a normalized representation.
pub fn signature_help_from_value(value: &Value) -> Option<LspSignatureHelp> {
    if value.is_null() {
        return None;
    }
    let signatures = value
        .get("signatures")
        .and_then(Value::as_array)?
        .iter()
        .filter_map(signature_from_value)
        .collect::<Vec<_>>();
    let active_signature = value
        .get("activeSignature")
        .and_then(Value::as_u64)
        .map(u64_to_u32_saturating);
    let active_parameter = value
        .get("activeParameter")
        .and_then(Value::as_u64)
        .map(u64_to_u32_saturating);
    Some(LspSignatureHelp {
        signatures,
        active_signature,
        active_parameter,
    })
}

impl LspSignatureHelp {
    /// Render the active signature help as a small single string.
    ///
    /// This is intended for simple UIs (status bars, tooltips). Rich UIs should render the typed
    /// model directly.
    pub fn to_compact_string(&self) -> Option<String> {
        let idx = usize::try_from(self.active_signature.unwrap_or(0)).ok()?;
        let sig = self.signatures.get(idx)?;
        Some(sig.label.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn signature_help_parses_basic_shape() {
        let v = json!({
            "signatures": [
                { "label": "add(a: i32, b: i32) -> i32" }
            ],
            "activeSignature": 0,
            "activeParameter": 1
        });
        let sh = signature_help_from_value(&v).expect("signature help");
        assert_eq!(sh.signatures.len(), 1);
        assert_eq!(sh.active_parameter, Some(1));
        assert_eq!(
            sh.to_compact_string().unwrap(),
            "add(a: i32, b: i32) -> i32"
        );
    }

    #[test]
    fn signature_help_parses_parameter_label_offsets() {
        let v = json!({
            "signatures": [
                {
                    "label": "add(a, b)",
                    "parameters": [
                        { "label": [4, 5] },
                        { "label": [7, 8] }
                    ]
                }
            ]
        });
        let sh = signature_help_from_value(&v).expect("signature help");
        assert_eq!(sh.signatures[0].parameters.len(), 2);
        assert_eq!(
            sh.signatures[0].parameters[0].label,
            Some(LspParameterLabel::Offsets(4, 5))
        );
    }
}
