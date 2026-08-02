use super::*;

pub(crate) fn parse_lsp_formatting_options(
    formatting_options_json: &str,
) -> Result<serde_json::Value, UiError> {
    if formatting_options_json.trim().is_empty() {
        Ok(serde_json::json!({
            "tabSize": 4,
            "insertSpaces": true,
        }))
    } else {
        serde_json::from_str(formatting_options_json).map_err(|e| UiError::Processor(e.to_string()))
    }
}

pub(crate) fn parse_lsp_position_list_json(
    positions_json: &str,
) -> Result<Vec<(usize, usize)>, UiError> {
    let value: serde_json::Value =
        serde_json::from_str(positions_json).map_err(|e| UiError::Processor(e.to_string()))?;
    let positions = value.as_array().ok_or_else(|| {
        UiError::Processor("selection range positions must be an array".to_string())
    })?;

    positions
        .iter()
        .map(|position| {
            let line = position
                .get("line")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing line".to_string())
                })?;
            let column = position
                .get("column")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing column".to_string())
                })?;
            let line = usize::try_from(line)
                .map_err(|_| UiError::Processor("selection range line is too large".to_string()))?;
            let column = usize::try_from(column).map_err(|_| {
                UiError::Processor("selection range column is too large".to_string())
            })?;
            Ok((line, column))
        })
        .collect()
}

pub(crate) fn parse_lsp_json_array(
    value_json: &str,
    name: &str,
) -> Result<Vec<serde_json::Value>, UiError> {
    if value_json.trim().is_empty() {
        return Ok(Vec::new());
    }

    let value: serde_json::Value =
        serde_json::from_str(value_json).map_err(|e| UiError::Processor(e.to_string()))?;
    value
        .as_array()
        .cloned()
        .ok_or_else(|| UiError::Processor(format!("{name} must be a JSON array")))
}
