use super::*;

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
