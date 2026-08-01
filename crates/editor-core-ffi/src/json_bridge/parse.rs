use super::*;

pub(crate) fn parse_command_from_json(json_text: &str) -> Result<Command, String> {
    let input: FfiCommandInput = parse_json(json_text, "command")?;
    Ok(input.into_core())
}

pub(crate) fn parse_processing_edits(json_text: &str) -> Result<Vec<ProcessingEdit>, String> {
    let input: FfiProcessingEditsInput = parse_json(json_text, "processing edits")?;
    Ok(input.into_core())
}
