use super::super::*;

pub(super) fn line_command(input: FfiEditCommandInput) -> Result<EditCommand, String> {
    Ok(match input {
        FfiEditCommandInput::Indent => EditCommand::Indent,
        FfiEditCommandInput::Outdent => EditCommand::Outdent,
        FfiEditCommandInput::DuplicateLines => EditCommand::DuplicateLines,
        FfiEditCommandInput::DeleteLines => EditCommand::DeleteLines,
        FfiEditCommandInput::MoveLinesUp => EditCommand::MoveLinesUp,
        FfiEditCommandInput::MoveLinesDown => EditCommand::MoveLinesDown,
        FfiEditCommandInput::JoinLines => EditCommand::JoinLines,
        FfiEditCommandInput::SplitLine => EditCommand::SplitLine,
        FfiEditCommandInput::ToggleComment { config } => EditCommand::ToggleComment {
            config: config.into(),
        },
        _ => unreachable!("non-line edit command routed to line converter"),
    })
}
