use super::*;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiOffsetRange {
    pub(crate) start: usize,
    pub(crate) end: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiUtf16Position {
    line: u32,
    character: u32,
}

impl From<FfiUtf16Position> for Utf16Position {
    fn from(value: FfiUtf16Position) -> Self {
        Utf16Position::new(value.line, value.character)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiUtf16Range {
    start: FfiUtf16Position,
    end: FfiUtf16Position,
}

impl From<FfiUtf16Range> for Utf16Range {
    fn from(value: FfiUtf16Range) -> Self {
        Utf16Range::new(value.start.into(), value.end.into())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiSymbolLocation {
    uri: String,
    range: FfiUtf16Range,
}

impl From<FfiSymbolLocation> for SymbolLocation {
    fn from(value: FfiSymbolLocation) -> Self {
        SymbolLocation {
            uri: value.uri,
            range: value.range.into(),
        }
    }
}
