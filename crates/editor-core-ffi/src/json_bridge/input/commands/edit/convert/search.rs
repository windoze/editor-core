use super::super::*;

pub(super) fn search_command(input: FfiEditCommandInput) -> Result<EditCommand, String> {
    Ok(match input {
        FfiEditCommandInput::ReplaceCurrent {
            query,
            replacement,
            options,
        } => EditCommand::ReplaceCurrent {
            query,
            replacement,
            options: options.into(),
        },
        FfiEditCommandInput::ReplaceAll {
            query,
            replacement,
            options,
        } => EditCommand::ReplaceAll {
            query,
            replacement,
            options: options.into(),
        },
        _ => unreachable!("non-search edit command routed to search converter"),
    })
}
