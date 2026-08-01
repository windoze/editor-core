use super::super::*;
use super::primitives::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiCommandInput {
    Edit {
        #[serde(flatten)]
        op: FfiEditCommandInput,
    },
    Cursor {
        #[serde(flatten)]
        op: FfiCursorCommandInput,
    },
    View {
        #[serde(flatten)]
        op: FfiViewCommandInput,
    },
    Style {
        #[serde(flatten)]
        op: FfiStyleCommandInput,
    },
}

impl FfiCommandInput {
    pub(crate) fn into_core(self) -> Command {
        match self {
            Self::Edit { op } => Command::Edit(op.into_core()),
            Self::Cursor { op } => Command::Cursor(op.into_core()),
            Self::View { op } => Command::View(op.into_core()),
            Self::Style { op } => Command::Style(op.into_core()),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiEditCommandInput {
    Insert {
        offset: usize,
        text: String,
    },
    Delete {
        start: usize,
        length: usize,
    },
    Replace {
        start: usize,
        length: usize,
        text: String,
    },
    InsertText {
        text: String,
    },
    InsertTab,
    InsertNewline {
        #[serde(default)]
        auto_indent: bool,
    },
    Indent,
    Outdent,
    DuplicateLines,
    DeleteLines,
    MoveLinesUp,
    MoveLinesDown,
    JoinLines,
    SplitLine,
    ToggleComment {
        config: FfiCommentConfig,
    },
    ApplyTextEdits {
        edits: Vec<FfiTextEditSpec>,
    },
    DeleteToPrevTabStop,
    DeleteGraphemeBack,
    DeleteGraphemeForward,
    DeleteWordBack,
    DeleteWordForward,
    Backspace,
    DeleteForward,
    Undo,
    Redo,
    EndUndoGroup,
    ReplaceCurrent {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    ReplaceAll {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
}

impl FfiEditCommandInput {
    fn into_core(self) -> EditCommand {
        match self {
            Self::Insert { offset, text } => EditCommand::Insert { offset, text },
            Self::Delete { start, length } => EditCommand::Delete { start, length },
            Self::Replace {
                start,
                length,
                text,
            } => EditCommand::Replace {
                start,
                length,
                text,
            },
            Self::InsertText { text } => EditCommand::InsertText { text },
            Self::InsertTab => EditCommand::InsertTab,
            Self::InsertNewline { auto_indent } => EditCommand::InsertNewline { auto_indent },
            Self::Indent => EditCommand::Indent,
            Self::Outdent => EditCommand::Outdent,
            Self::DuplicateLines => EditCommand::DuplicateLines,
            Self::DeleteLines => EditCommand::DeleteLines,
            Self::MoveLinesUp => EditCommand::MoveLinesUp,
            Self::MoveLinesDown => EditCommand::MoveLinesDown,
            Self::JoinLines => EditCommand::JoinLines,
            Self::SplitLine => EditCommand::SplitLine,
            Self::ToggleComment { config } => EditCommand::ToggleComment {
                config: config.into(),
            },
            Self::ApplyTextEdits { edits } => EditCommand::ApplyTextEdits {
                edits: edits.into_iter().map(Into::into).collect(),
            },
            Self::DeleteToPrevTabStop => EditCommand::DeleteToPrevTabStop,
            Self::DeleteGraphemeBack => EditCommand::DeleteGraphemeBack,
            Self::DeleteGraphemeForward => EditCommand::DeleteGraphemeForward,
            Self::DeleteWordBack => EditCommand::DeleteWordBack,
            Self::DeleteWordForward => EditCommand::DeleteWordForward,
            Self::Backspace => EditCommand::Backspace,
            Self::DeleteForward => EditCommand::DeleteForward,
            Self::Undo => EditCommand::Undo,
            Self::Redo => EditCommand::Redo,
            Self::EndUndoGroup => EditCommand::EndUndoGroup,
            Self::ReplaceCurrent {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceCurrent {
                query,
                replacement,
                options: options.into(),
            },
            Self::ReplaceAll {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceAll {
                query,
                replacement,
                options: options.into(),
            },
        }
    }
}

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
}

impl FfiCursorCommandInput {
    fn into_core(self) -> CursorCommand {
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
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiViewCommandInput {
    SetViewportWidth { width: usize },
    SetWrapMode { mode: FfiWrapMode },
    SetWrapIndent { indent: FfiWrapIndent },
    SetTabWidth { width: usize },
    SetTabKeyBehavior { behavior: FfiTabKeyBehavior },
    SetIndentationConfig { config: FfiIndentationConfig },
    SetWordBoundaryAsciiBoundaryChars { boundary_chars: String },
    ResetWordBoundaryDefaults,
    ScrollTo { line: usize },
    GetViewport { start_row: usize, count: usize },
}

impl FfiViewCommandInput {
    fn into_core(self) -> ViewCommand {
        match self {
            Self::SetViewportWidth { width } => ViewCommand::SetViewportWidth { width },
            Self::SetWrapMode { mode } => ViewCommand::SetWrapMode { mode: mode.into() },
            Self::SetWrapIndent { indent } => ViewCommand::SetWrapIndent {
                indent: indent.into(),
            },
            Self::SetTabWidth { width } => ViewCommand::SetTabWidth { width },
            Self::SetTabKeyBehavior { behavior } => ViewCommand::SetTabKeyBehavior {
                behavior: behavior.into(),
            },
            Self::SetIndentationConfig { config } => ViewCommand::SetIndentationConfig {
                config: config.into(),
            },
            Self::SetWordBoundaryAsciiBoundaryChars { boundary_chars } => {
                ViewCommand::SetWordBoundaryAsciiBoundaryChars { boundary_chars }
            }
            Self::ResetWordBoundaryDefaults => ViewCommand::ResetWordBoundaryDefaults,
            Self::ScrollTo { line } => ViewCommand::ScrollTo { line },
            Self::GetViewport { start_row, count } => ViewCommand::GetViewport { start_row, count },
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiStyleCommandInput {
    AddStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    RemoveStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    Fold {
        start_line: usize,
        end_line: usize,
    },
    Unfold {
        start_line: usize,
    },
    UnfoldAll,
}

impl FfiStyleCommandInput {
    fn into_core(self) -> StyleCommand {
        match self {
            Self::AddStyle {
                start,
                end,
                style_id,
            } => StyleCommand::AddStyle {
                start,
                end,
                style_id,
            },
            Self::RemoveStyle {
                start,
                end,
                style_id,
            } => StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            },
            Self::Fold {
                start_line,
                end_line,
            } => StyleCommand::Fold {
                start_line,
                end_line,
            },
            Self::Unfold { start_line } => StyleCommand::Unfold { start_line },
            Self::UnfoldAll => StyleCommand::UnfoldAll,
        }
    }
}
