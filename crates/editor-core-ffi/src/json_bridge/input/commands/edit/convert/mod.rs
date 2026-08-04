mod content;
mod deletion;
mod line;
mod search;
mod structured;

use super::*;

impl FfiEditCommandInput {
    pub(crate) fn try_into_core(self) -> Result<EditCommand, String> {
        match self {
            input @ (Self::Insert { .. }
            | Self::Replace { .. }
            | Self::ReplaceCoalescingUndo { .. }
            | Self::ReplaceCoalescingUndoWithSelection { .. }
            | Self::InsertText { .. }
            | Self::TypeChar { .. }
            | Self::InsertTab
            | Self::InsertNewline { .. }) => content::content_command(input),
            input @ (Self::Indent
            | Self::Outdent
            | Self::DuplicateLines
            | Self::DeleteLines
            | Self::MoveLinesUp
            | Self::MoveLinesDown
            | Self::JoinLines
            | Self::SplitLine
            | Self::ToggleComment { .. }) => line::line_command(input),
            input @ (Self::ApplyTextEdits { .. } | Self::ApplySnippet { .. }) => {
                structured::structured_command(input)
            }
            input @ (Self::Delete { .. }
            | Self::DeleteToPrevTabStop
            | Self::DeleteGraphemeBack
            | Self::DeleteGraphemeForward
            | Self::DeleteWordBack
            | Self::DeleteWordForward
            | Self::Backspace
            | Self::DeleteForward
            | Self::Undo
            | Self::Redo
            | Self::EndUndoGroup) => deletion::deletion_command(input),
            input @ (Self::ReplaceCurrent { .. } | Self::ReplaceAll { .. }) => {
                search::search_command(input)
            }
        }
    }
}
