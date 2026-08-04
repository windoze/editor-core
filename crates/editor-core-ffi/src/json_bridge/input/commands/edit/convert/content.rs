use super::super::*;

pub(super) fn content_command(input: FfiEditCommandInput) -> Result<EditCommand, String> {
    Ok(match input {
        FfiEditCommandInput::Insert { offset, text } => EditCommand::Insert { offset, text },
        FfiEditCommandInput::Replace {
            start,
            length,
            text,
        } => EditCommand::Replace {
            start,
            length,
            text,
        },
        FfiEditCommandInput::ReplaceCoalescingUndo {
            start,
            length,
            text,
        } => EditCommand::ReplaceCoalescingUndo {
            start,
            length,
            text,
        },
        FfiEditCommandInput::ReplaceCoalescingUndoWithSelection {
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
        FfiEditCommandInput::InsertText { text } => EditCommand::InsertText { text },
        FfiEditCommandInput::TypeChar { ch } => EditCommand::TypeChar {
            ch: single_char(&ch, "ch")?,
        },
        FfiEditCommandInput::InsertTab => EditCommand::InsertTab,
        FfiEditCommandInput::InsertNewline { auto_indent } => {
            EditCommand::InsertNewline { auto_indent }
        }
        _ => unreachable!("non-content edit command routed to content converter"),
    })
}
