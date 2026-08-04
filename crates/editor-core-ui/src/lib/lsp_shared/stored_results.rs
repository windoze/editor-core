use super::LspResultSlot;
use crate::prelude::*;

pub(crate) fn stored_lsp_error_result_json(
    slot: LspResultSlot,
    error: LspResponseError,
) -> Option<String> {
    if slot != LspResultSlot::ExecuteCommand && slot != LspResultSlot::CodeLens {
        return None;
    }

    Some(
        serde_json::json!({
            "error": {
                "code": error.code,
                "message": error.message,
                "data": error.data,
            }
        })
        .to_string(),
    )
}

pub(crate) fn stored_lsp_success_result_json(
    slot: LspResultSlot,
    result: serde_json::Value,
) -> Option<String> {
    if slot == LspResultSlot::ExecuteCommand {
        return Some(serde_json::json!({ "result": result }).to_string());
    }
    if slot == LspResultSlot::CodeLens {
        return Some(result.to_string());
    }

    if result.is_null() {
        None
    } else {
        Some(result.to_string())
    }
}
