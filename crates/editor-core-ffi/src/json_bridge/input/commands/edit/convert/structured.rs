use super::super::*;

pub(super) fn structured_command(input: FfiEditCommandInput) -> Result<EditCommand, String> {
    Ok(match input {
        FfiEditCommandInput::ApplyTextEdits { edits } => EditCommand::ApplyTextEdits {
            edits: edits.into_iter().map(Into::into).collect(),
        },
        FfiEditCommandInput::ApplySnippet {
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
        _ => unreachable!("non-structured edit command routed to structured converter"),
    })
}
