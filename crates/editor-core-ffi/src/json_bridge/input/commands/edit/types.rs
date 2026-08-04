use super::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiEditCommandInput {
    Insert {
        offset: usize,
        text: String,
    },
    Delete {
        start: usize,
        length: usize,
    },
    Replace {
        start: usize,
        length: usize,
        text: String,
    },
    ReplaceCoalescingUndo {
        start: usize,
        length: usize,
        text: String,
    },
    ReplaceCoalescingUndoWithSelection {
        start: usize,
        length: usize,
        text: String,
        selection_start: usize,
        selection_end: usize,
    },
    InsertText {
        text: String,
    },
    TypeChar {
        ch: String,
    },
    InsertTab,
    InsertNewline {
        #[serde(default)]
        auto_indent: bool,
    },
    Indent,
    Outdent,
    DuplicateLines,
    DeleteLines,
    MoveLinesUp,
    MoveLinesDown,
    JoinLines,
    SplitLine,
    ToggleComment {
        config: FfiCommentConfig,
    },
    ApplyTextEdits {
        edits: Vec<FfiTextEditSpec>,
    },
    ApplySnippet {
        start: usize,
        end: usize,
        snippet: String,
        #[serde(default)]
        additional_edits: Vec<FfiTextEditSpec>,
    },
    DeleteToPrevTabStop,
    DeleteGraphemeBack,
    DeleteGraphemeForward,
    DeleteWordBack,
    DeleteWordForward,
    Backspace,
    DeleteForward,
    Undo,
    Redo,
    EndUndoGroup,
    ReplaceCurrent {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    ReplaceAll {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
}
