use super::*;

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
