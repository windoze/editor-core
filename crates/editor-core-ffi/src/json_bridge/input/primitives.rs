use super::super::*;

pub(crate) fn line_ending_from_str(s: &str) -> Result<LineEnding, String> {
    match s.trim().to_ascii_lowercase().as_str() {
        "lf" => Ok(LineEnding::Lf),
        "crlf" => Ok(LineEnding::Crlf),
        other => Err(format!(
            "unsupported line ending: {other} (expected lf|crlf)"
        )),
    }
}

pub(crate) fn line_ending_to_str(line_ending: LineEnding) -> &'static str {
    match line_ending {
        LineEnding::Lf => "lf",
        LineEnding::Crlf => "crlf",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiPosition {
    line: usize,
    column: usize,
}

impl From<FfiPosition> for Position {
    fn from(value: FfiPosition) -> Self {
        Position::new(value.line, value.column)
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiSelectionDirection {
    Forward,
    Backward,
}

impl From<FfiSelectionDirection> for SelectionDirection {
    fn from(value: FfiSelectionDirection) -> Self {
        match value {
            FfiSelectionDirection::Forward => SelectionDirection::Forward,
            FfiSelectionDirection::Backward => SelectionDirection::Backward,
        }
    }
}

pub(crate) fn selection_direction_to_str(direction: SelectionDirection) -> &'static str {
    match direction {
        SelectionDirection::Forward => "forward",
        SelectionDirection::Backward => "backward",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiSelection {
    start: FfiPosition,
    end: FfiPosition,
    direction: FfiSelectionDirection,
}

impl From<FfiSelection> for Selection {
    fn from(value: FfiSelection) -> Self {
        Selection {
            start: value.start.into(),
            end: value.end.into(),
            direction: value.direction.into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiTextEditSpec {
    start: usize,
    end: usize,
    text: String,
}

impl From<FfiTextEditSpec> for TextEditSpec {
    fn from(value: FfiTextEditSpec) -> Self {
        TextEditSpec {
            start: value.start,
            end: value.end,
            text: value.text,
        }
    }
}

pub(crate) fn single_char(value: &str, field_name: &str) -> Result<char, String> {
    let mut chars = value.chars();
    let Some(ch) = chars.next() else {
        return Err(format!("{field_name} must be exactly one character"));
    };
    if chars.next().is_some() {
        return Err(format!("{field_name} must be exactly one character"));
    }
    Ok(ch)
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiAutoPair {
    open: String,
    close: String,
}

impl FfiAutoPair {
    pub(crate) fn try_into_core(self) -> Result<AutoPair, String> {
        Ok(AutoPair {
            open: single_char(&self.open, "auto pair open")?,
            close: single_char(&self.close, "auto pair close")?,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiAutoPairsConfig {
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    pairs: Option<Vec<FfiAutoPair>>,
    #[serde(default)]
    wrap_selection: Option<bool>,
    #[serde(default)]
    skip_over_closing: Option<bool>,
    #[serde(default)]
    delete_pair: Option<bool>,
}

impl FfiAutoPairsConfig {
    pub(crate) fn try_into_core(self) -> Result<AutoPairsConfig, String> {
        let mut cfg = AutoPairsConfig::default();
        if let Some(enabled) = self.enabled {
            cfg.enabled = enabled;
        }
        if let Some(pairs) = self.pairs {
            cfg.pairs = pairs
                .into_iter()
                .map(FfiAutoPair::try_into_core)
                .collect::<Result<Vec<_>, _>>()?;
        }
        if let Some(wrap_selection) = self.wrap_selection {
            cfg.wrap_selection = wrap_selection;
        }
        if let Some(skip_over_closing) = self.skip_over_closing {
            cfg.skip_over_closing = skip_over_closing;
        }
        if let Some(delete_pair) = self.delete_pair {
            cfg.delete_pair = delete_pair;
        }
        Ok(cfg)
    }
}

pub(crate) fn default_case_sensitive() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub(crate) struct FfiSearchOptions {
    #[serde(default = "default_case_sensitive")]
    case_sensitive: bool,
    #[serde(default)]
    whole_word: bool,
    #[serde(default)]
    regex: bool,
}

impl Default for FfiSearchOptions {
    fn default() -> Self {
        Self {
            case_sensitive: true,
            whole_word: false,
            regex: false,
        }
    }
}

impl From<FfiSearchOptions> for SearchOptions {
    fn from(value: FfiSearchOptions) -> Self {
        SearchOptions {
            case_sensitive: value.case_sensitive,
            whole_word: value.whole_word,
            regex: value.regex,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiCommentConfig {
    line: Option<String>,
    block_start: Option<String>,
    block_end: Option<String>,
}

impl From<FfiCommentConfig> for editor_core::CommentConfig {
    fn from(value: FfiCommentConfig) -> Self {
        editor_core::CommentConfig {
            line: value.line,
            block_start: value.block_start,
            block_end: value.block_end,
        }
    }
}

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
