use crate::*;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiFoldRegionInput {
    start_line: usize,
    end_line: usize,
    #[serde(default)]
    is_collapsed: bool,
    #[serde(default = "default_fold_placeholder")]
    placeholder: String,
}

pub(crate) fn default_fold_placeholder() -> String {
    "[...]".to_string()
}

impl From<FfiFoldRegionInput> for FoldRegion {
    fn from(value: FfiFoldRegionInput) -> Self {
        FoldRegion {
            start_line: value.start_line,
            end_line: value.end_line,
            is_collapsed: value.is_collapsed,
            placeholder: value.placeholder,
        }
    }
}
