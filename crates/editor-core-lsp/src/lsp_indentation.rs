//! LSP indentation helpers (on-type formatting + formatting options).
//!
//! This module is intentionally lightweight:
//! - It does not depend on `lsp-types`.
//! - It focuses on the subset typically needed for "auto-indent" behavior on newline
//!   (`textDocument/onTypeFormatting` + `FormattingOptions`).

use editor_core::{IndentStyle, IndentationConfig};
use serde_json::{Value, json};

/// `documentOnTypeFormattingProvider` information parsed from server capabilities.
///
/// This corresponds to LSP `DocumentOnTypeFormattingOptions`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspOnTypeFormattingOptions {
    /// The first trigger character (required by LSP when the provider exists).
    pub first_trigger_character: String,
    /// Additional trigger characters (optional).
    pub more_trigger_characters: Vec<String>,
}

impl LspOnTypeFormattingOptions {
    /// Return all trigger characters (first + more).
    pub fn all_trigger_characters(&self) -> Vec<String> {
        let mut out = Vec::with_capacity(1 + self.more_trigger_characters.len());
        out.push(self.first_trigger_character.clone());
        out.extend(self.more_trigger_characters.iter().cloned());
        out
    }

    /// Return `true` if `ch` is one of the configured trigger characters.
    pub fn is_trigger_character(&self, ch: &str) -> bool {
        if self.first_trigger_character == ch {
            return true;
        }
        self.more_trigger_characters.iter().any(|c| c == ch)
    }
}

/// Parse `documentOnTypeFormattingProvider` from an LSP server `capabilities` JSON value.
pub fn on_type_formatting_options_from_capabilities(
    capabilities: &Value,
) -> Option<LspOnTypeFormattingOptions> {
    let provider = capabilities.get("documentOnTypeFormattingProvider")?;
    let provider = provider.as_object()?;

    let first_trigger_character = provider
        .get("firstTriggerCharacter")
        .and_then(Value::as_str)?
        .to_string();

    let more_trigger_characters = provider
        .get("moreTriggerCharacter")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(|s| s.to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Some(LspOnTypeFormattingOptions {
        first_trigger_character,
        more_trigger_characters,
    })
}

/// Build a minimal LSP `FormattingOptions` JSON object.
///
/// Notes:
/// - This returns only `tabSize` and `insertSpaces`, which most servers use for indentation.
pub fn lsp_formatting_options(tab_size: usize, insert_spaces: bool) -> Value {
    json!({
        "tabSize": tab_size.max(1),
        "insertSpaces": insert_spaces,
    })
}

/// Build LSP `FormattingOptions` from `editor-core` indentation configuration.
pub fn lsp_formatting_options_for_indentation_config(
    config: &IndentationConfig,
    tab_width: usize,
) -> Value {
    match config.style {
        IndentStyle::Tabs => lsp_formatting_options(tab_width, false),
        IndentStyle::Spaces(width) => lsp_formatting_options(width as usize, true),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_on_type_formatting_options() {
        let caps = json!({
            "documentOnTypeFormattingProvider": {
                "firstTriggerCharacter": "\n",
                "moreTriggerCharacter": ["}", ";"]
            }
        });

        let opts = on_type_formatting_options_from_capabilities(&caps).unwrap();
        assert_eq!(opts.first_trigger_character, "\n");
        assert_eq!(
            opts.more_trigger_characters,
            vec!["}".to_string(), ";".to_string()]
        );
        assert!(opts.is_trigger_character("\n"));
        assert!(opts.is_trigger_character("}"));
        assert!(!opts.is_trigger_character("{"));
    }

    #[test]
    fn formatting_options_from_indent_config_spaces() {
        let config = IndentationConfig {
            style: IndentStyle::Spaces(2),
            indent_triggers: vec![],
            outdent_triggers: vec![],
        };

        let options = lsp_formatting_options_for_indentation_config(&config, 8);
        assert_eq!(options, json!({ "tabSize": 2, "insertSpaces": true }));
    }

    #[test]
    fn formatting_options_from_indent_config_tabs() {
        let config = IndentationConfig {
            style: IndentStyle::Tabs,
            indent_triggers: vec![],
            outdent_triggers: vec![],
        };

        let options = lsp_formatting_options_for_indentation_config(&config, 4);
        assert_eq!(options, json!({ "tabSize": 4, "insertSpaces": false }));
    }
}
