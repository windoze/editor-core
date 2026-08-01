use super::*;

impl FfiEditCommandInput {
    pub(crate) fn try_into_core(self) -> Result<EditCommand, String> {
        Ok(match self {
            Self::Insert { offset, text } => EditCommand::Insert { offset, text },
            Self::Delete { start, length } => EditCommand::Delete { start, length },
            Self::Replace {
                start,
                length,
                text,
            } => EditCommand::Replace {
                start,
                length,
                text,
            },
            Self::ReplaceCoalescingUndo {
                start,
                length,
                text,
            } => EditCommand::ReplaceCoalescingUndo {
                start,
                length,
                text,
            },
            Self::ReplaceCoalescingUndoWithSelection {
                start,
                length,
                text,
                selection_start,
                selection_end,
            } => EditCommand::ReplaceCoalescingUndoWithSelection {
                start,
                length,
                text,
                selection_start,
                selection_end,
            },
            Self::InsertText { text } => EditCommand::InsertText { text },
            Self::TypeChar { ch } => EditCommand::TypeChar {
                ch: single_char(&ch, "ch")?,
            },
            Self::InsertTab => EditCommand::InsertTab,
            Self::InsertNewline { auto_indent } => EditCommand::InsertNewline { auto_indent },
            Self::Indent => EditCommand::Indent,
            Self::Outdent => EditCommand::Outdent,
            Self::DuplicateLines => EditCommand::DuplicateLines,
            Self::DeleteLines => EditCommand::DeleteLines,
            Self::MoveLinesUp => EditCommand::MoveLinesUp,
            Self::MoveLinesDown => EditCommand::MoveLinesDown,
            Self::JoinLines => EditCommand::JoinLines,
            Self::SplitLine => EditCommand::SplitLine,
            Self::ToggleComment { config } => EditCommand::ToggleComment {
                config: config.into(),
            },
            Self::ApplyTextEdits { edits } => EditCommand::ApplyTextEdits {
                edits: edits.into_iter().map(Into::into).collect(),
            },
            Self::ApplySnippet {
                start,
                end,
                snippet,
                additional_edits,
            } => EditCommand::ApplySnippet {
                start,
                end,
                snippet,
                additional_edits: additional_edits.into_iter().map(Into::into).collect(),
            },
            Self::DeleteToPrevTabStop => EditCommand::DeleteToPrevTabStop,
            Self::DeleteGraphemeBack => EditCommand::DeleteGraphemeBack,
            Self::DeleteGraphemeForward => EditCommand::DeleteGraphemeForward,
            Self::DeleteWordBack => EditCommand::DeleteWordBack,
            Self::DeleteWordForward => EditCommand::DeleteWordForward,
            Self::Backspace => EditCommand::Backspace,
            Self::DeleteForward => EditCommand::DeleteForward,
            Self::Undo => EditCommand::Undo,
            Self::Redo => EditCommand::Redo,
            Self::EndUndoGroup => EditCommand::EndUndoGroup,
            Self::ReplaceCurrent {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceCurrent {
                query,
                replacement,
                options: options.into(),
            },
            Self::ReplaceAll {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceAll {
                query,
                replacement,
                options: options.into(),
            },
        })
    }
}
