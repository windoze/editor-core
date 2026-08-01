use super::*;

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
