use super::*;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiExpandSelectionUnit {
    Character,
    Word,
    Line,
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiExpandSelectionDirection {
    Backward,
    Forward,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiCursorCommandInput {
    MoveTo {
        line: usize,
        column: usize,
    },
    MoveBy {
        delta_line: isize,
        delta_column: isize,
    },
    MoveVisualBy {
        delta_rows: isize,
    },
    MoveToVisual {
        row: usize,
        x_cells: usize,
    },
    MoveToLineStart,
    MoveToLineEnd,
    MoveToVisualLineStart,
    MoveToVisualLineEnd,
    MoveGraphemeLeft,
    MoveGraphemeRight,
    MoveWordLeft,
    MoveWordRight,
    MoveToMatchingBracket,
    SetSelection {
        start: FfiPosition,
        end: FfiPosition,
    },
    ExtendSelection {
        to: FfiPosition,
    },
    ClearSelection,
    SetSelections {
        selections: Vec<FfiSelection>,
        primary_index: usize,
    },
    ClearSecondarySelections,
    SetRectSelection {
        anchor: FfiPosition,
        active: FfiPosition,
    },
    SelectLine,
    SelectWord,
    ExpandSelection,
    ExpandSelectionBy {
        unit: FfiExpandSelectionUnit,
        count: usize,
        direction: FfiExpandSelectionDirection,
    },
    AddCursorAbove,
    AddCursorBelow,
    AddNextOccurrence {
        #[serde(default)]
        options: FfiSearchOptions,
    },
    AddAllOccurrences {
        #[serde(default)]
        options: FfiSearchOptions,
    },
    FindNext {
        query: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    FindPrev {
        query: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    SnippetNextPlaceholder,
    SnippetPrevPlaceholder,
}
