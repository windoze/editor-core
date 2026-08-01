use super::*;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiExpandSelectionUnit {
    Character,
    Word,
    Line,
}

impl From<FfiExpandSelectionUnit> for ExpandSelectionUnit {
    fn from(value: FfiExpandSelectionUnit) -> Self {
        match value {
            FfiExpandSelectionUnit::Character => ExpandSelectionUnit::Character,
            FfiExpandSelectionUnit::Word => ExpandSelectionUnit::Word,
            FfiExpandSelectionUnit::Line => ExpandSelectionUnit::Line,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiExpandSelectionDirection {
    Backward,
    Forward,
}

impl From<FfiExpandSelectionDirection> for ExpandSelectionDirection {
    fn from(value: FfiExpandSelectionDirection) -> Self {
        match value {
            FfiExpandSelectionDirection::Backward => ExpandSelectionDirection::Backward,
            FfiExpandSelectionDirection::Forward => ExpandSelectionDirection::Forward,
        }
    }
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

impl FfiCursorCommandInput {
    pub(super) fn into_core(self) -> CursorCommand {
        match self {
            Self::MoveTo { line, column } => CursorCommand::MoveTo { line, column },
            Self::MoveBy {
                delta_line,
                delta_column,
            } => CursorCommand::MoveBy {
                delta_line,
                delta_column,
            },
            Self::MoveVisualBy { delta_rows } => CursorCommand::MoveVisualBy { delta_rows },
            Self::MoveToVisual { row, x_cells } => CursorCommand::MoveToVisual { row, x_cells },
            Self::MoveToLineStart => CursorCommand::MoveToLineStart,
            Self::MoveToLineEnd => CursorCommand::MoveToLineEnd,
            Self::MoveToVisualLineStart => CursorCommand::MoveToVisualLineStart,
            Self::MoveToVisualLineEnd => CursorCommand::MoveToVisualLineEnd,
            Self::MoveGraphemeLeft => CursorCommand::MoveGraphemeLeft,
            Self::MoveGraphemeRight => CursorCommand::MoveGraphemeRight,
            Self::MoveWordLeft => CursorCommand::MoveWordLeft,
            Self::MoveWordRight => CursorCommand::MoveWordRight,
            Self::MoveToMatchingBracket => CursorCommand::MoveToMatchingBracket,
            Self::SetSelection { start, end } => CursorCommand::SetSelection {
                start: start.into(),
                end: end.into(),
            },
            Self::ExtendSelection { to } => CursorCommand::ExtendSelection { to: to.into() },
            Self::ClearSelection => CursorCommand::ClearSelection,
            Self::SetSelections {
                selections,
                primary_index,
            } => CursorCommand::SetSelections {
                selections: selections.into_iter().map(Into::into).collect(),
                primary_index,
            },
            Self::ClearSecondarySelections => CursorCommand::ClearSecondarySelections,
            Self::SetRectSelection { anchor, active } => CursorCommand::SetRectSelection {
                anchor: anchor.into(),
                active: active.into(),
            },
            Self::SelectLine => CursorCommand::SelectLine,
            Self::SelectWord => CursorCommand::SelectWord,
            Self::ExpandSelection => CursorCommand::ExpandSelection,
            Self::ExpandSelectionBy {
                unit,
                count,
                direction,
            } => CursorCommand::ExpandSelectionBy {
                unit: unit.into(),
                count,
                direction: direction.into(),
            },
            Self::AddCursorAbove => CursorCommand::AddCursorAbove,
            Self::AddCursorBelow => CursorCommand::AddCursorBelow,
            Self::AddNextOccurrence { options } => CursorCommand::AddNextOccurrence {
                options: options.into(),
            },
            Self::AddAllOccurrences { options } => CursorCommand::AddAllOccurrences {
                options: options.into(),
            },
            Self::FindNext { query, options } => CursorCommand::FindNext {
                query,
                options: options.into(),
            },
            Self::FindPrev { query, options } => CursorCommand::FindPrev {
                query,
                options: options.into(),
            },
            Self::SnippetNextPlaceholder => CursorCommand::SnippetNextPlaceholder,
            Self::SnippetPrevPlaceholder => CursorCommand::SnippetPrevPlaceholder,
        }
    }
}
