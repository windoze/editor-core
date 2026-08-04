use super::super::*;
use crate::*;

pub(crate) fn value_command_result(result: CommandResult) -> Value {
    match result {
        CommandResult::Success => json!({ "kind": "success" }),
        CommandResult::Text(text) => json!({ "kind": "text", "text": text }),
        CommandResult::Position(pos) => {
            json!({ "kind": "position", "position": value_position(pos) })
        }
        CommandResult::Offset(offset) => json!({ "kind": "offset", "offset": offset }),
        CommandResult::Viewport(grid) => {
            json!({ "kind": "viewport", "viewport": value_headless_grid(&grid) })
        }
        CommandResult::SearchMatch { start, end } => {
            json!({ "kind": "search_match", "start": start, "end": end })
        }
        CommandResult::SearchNotFound => json!({ "kind": "search_not_found" }),
        CommandResult::ReplaceResult { replaced } => {
            json!({ "kind": "replace_result", "replaced": replaced })
        }
    }
}
