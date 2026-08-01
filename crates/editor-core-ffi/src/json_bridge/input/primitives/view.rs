use super::*;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiTabKeyBehavior {
    Tab,
    Spaces,
}

impl From<FfiTabKeyBehavior> for TabKeyBehavior {
    fn from(value: FfiTabKeyBehavior) -> Self {
        match value {
            FfiTabKeyBehavior::Tab => TabKeyBehavior::Tab,
            FfiTabKeyBehavior::Spaces => TabKeyBehavior::Spaces,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiWrapMode {
    None,
    Char,
    Word,
}

impl From<FfiWrapMode> for WrapMode {
    fn from(value: FfiWrapMode) -> Self {
        match value {
            FfiWrapMode::None => WrapMode::None,
            FfiWrapMode::Char => WrapMode::Char,
            FfiWrapMode::Word => WrapMode::Word,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiWrapIndent {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<FfiWrapIndent> for WrapIndent {
    fn from(value: FfiWrapIndent) -> Self {
        match value {
            FfiWrapIndent::None => WrapIndent::None,
            FfiWrapIndent::SameAsLineIndent => WrapIndent::SameAsLineIndent,
            FfiWrapIndent::FixedCells { cells } => WrapIndent::FixedCells(cells),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiIndentStyle {
    Tabs,
    Spaces { width: u8 },
}

impl From<FfiIndentStyle> for IndentStyle {
    fn from(value: FfiIndentStyle) -> Self {
        match value {
            FfiIndentStyle::Tabs => IndentStyle::Tabs,
            FfiIndentStyle::Spaces { width } => IndentStyle::Spaces(width.max(1)),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiIndentationConfig {
    #[serde(default)]
    style: Option<FfiIndentStyle>,
    #[serde(default)]
    indent_triggers: Option<Vec<String>>,
    #[serde(default)]
    outdent_triggers: Option<Vec<String>>,
}

impl From<FfiIndentationConfig> for IndentationConfig {
    fn from(value: FfiIndentationConfig) -> Self {
        let mut cfg = IndentationConfig::default();

        if let Some(style) = value.style {
            cfg.style = style.into();
        }

        if let Some(triggers) = value.indent_triggers {
            cfg.indent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }

        if let Some(triggers) = value.outdent_triggers {
            cfg.outdent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }

        cfg
    }
}
