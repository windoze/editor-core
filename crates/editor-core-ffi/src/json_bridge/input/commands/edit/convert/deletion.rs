use super::super::*;

pub(super) fn deletion_command(input: FfiEditCommandInput) -> Result<EditCommand, String> {
    Ok(match input {
        FfiEditCommandInput::Delete { start, length } => EditCommand::Delete { start, length },
        FfiEditCommandInput::DeleteToPrevTabStop => EditCommand::DeleteToPrevTabStop,
        FfiEditCommandInput::DeleteGraphemeBack => EditCommand::DeleteGraphemeBack,
        FfiEditCommandInput::DeleteGraphemeForward => EditCommand::DeleteGraphemeForward,
        FfiEditCommandInput::DeleteWordBack => EditCommand::DeleteWordBack,
        FfiEditCommandInput::DeleteWordForward => EditCommand::DeleteWordForward,
        FfiEditCommandInput::Backspace => EditCommand::Backspace,
        FfiEditCommandInput::DeleteForward => EditCommand::DeleteForward,
        FfiEditCommandInput::Undo => EditCommand::Undo,
        FfiEditCommandInput::Redo => EditCommand::Redo,
        FfiEditCommandInput::EndUndoGroup => EditCommand::EndUndoGroup,
        _ => unreachable!("non-deletion edit command routed to deletion converter"),
    })
}
