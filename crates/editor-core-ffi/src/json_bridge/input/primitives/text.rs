use super::*;

pub(crate) fn line_ending_from_str(s: &str) -> Result<LineEnding, String> {
    match s.trim().to_ascii_lowercase().as_str() {
        "lf" => Ok(LineEnding::Lf),
        "crlf" => Ok(LineEnding::Crlf),
        other => Err(format!(
            "unsupported line ending: {other} (expected lf|crlf)"
        )),
    }
}

pub(crate) fn line_ending_to_str(line_ending: LineEnding) -> &'static str {
    match line_ending {
        LineEnding::Lf => "lf",
        LineEnding::Crlf => "crlf",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiPosition {
    line: usize,
    column: usize,
}

impl From<FfiPosition> for Position {
    fn from(value: FfiPosition) -> Self {
        Position::new(value.line, value.column)
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiSelectionDirection {
    Forward,
    Backward,
}

impl From<FfiSelectionDirection> for SelectionDirection {
    fn from(value: FfiSelectionDirection) -> Self {
        match value {
            FfiSelectionDirection::Forward => SelectionDirection::Forward,
            FfiSelectionDirection::Backward => SelectionDirection::Backward,
        }
    }
}

pub(crate) fn selection_direction_to_str(direction: SelectionDirection) -> &'static str {
    match direction {
        SelectionDirection::Forward => "forward",
        SelectionDirection::Backward => "backward",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiSelection {
    start: FfiPosition,
    end: FfiPosition,
    direction: FfiSelectionDirection,
}

impl From<FfiSelection> for Selection {
    fn from(value: FfiSelection) -> Self {
        Selection {
            start: value.start.into(),
            end: value.end.into(),
            direction: value.direction.into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiTextEditSpec {
    start: usize,
    end: usize,
    text: String,
}

impl From<FfiTextEditSpec> for TextEditSpec {
    fn from(value: FfiTextEditSpec) -> Self {
        TextEditSpec {
            start: value.start,
            end: value.end,
            text: value.text,
        }
    }
}

pub(crate) fn single_char(value: &str, field_name: &str) -> Result<char, String> {
    let mut chars = value.chars();
    let Some(ch) = chars.next() else {
        return Err(format!("{field_name} must be exactly one character"));
    };
    if chars.next().is_some() {
        return Err(format!("{field_name} must be exactly one character"));
    }
    Ok(ch)
}
