use editor_core::{
    AutoPair, AutoPairsConfig, Cell, Command, CommandResult, CursorCommand, EditCommand,
    ExpandSelectionDirection, ExpandSelectionUnit, HeadlessGrid, HeadlessLine, IndentStyle,
    IndentationConfig, Position, SearchOptions, Selection, SelectionDirection, StyleCommand,
    TabKeyBehavior, TextEditSpec, ViewCommand, WrapIndent, WrapMode,
};
use serde::Deserialize;
use serde_json::{Value, json};

pub(crate) fn parse_command_from_json(text: &str) -> Result<Command, String> {
    let input: JsonCommandInput =
        serde_json::from_str(text).map_err(|err| format!("invalid command JSON: {err}"))?;
    input.try_into_core()
}

pub(crate) fn command_result_to_value(result: CommandResult) -> Value {
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

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum JsonCommandInput {
    Edit {
        #[serde(flatten)]
        op: JsonEditCommandInput,
    },
    Cursor {
        #[serde(flatten)]
        op: JsonCursorCommandInput,
    },
    View {
        #[serde(flatten)]
        op: JsonViewCommandInput,
    },
    Style {
        #[serde(flatten)]
        op: JsonStyleCommandInput,
    },
}

impl JsonCommandInput {
    fn try_into_core(self) -> Result<Command, String> {
        match self {
            Self::Edit { op } => op.try_into_core().map(Command::Edit),
            Self::Cursor { op } => op.try_into_core().map(Command::Cursor),
            Self::View { op } => op.try_into_core().map(Command::View),
            Self::Style { op } => Ok(Command::Style(op.into_core())),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum JsonEditCommandInput {
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
    ReplaceCoalescingUndo {
        start: usize,
        length: usize,
        text: String,
    },
    ReplaceCoalescingUndoWithSelection {
        start: usize,
        length: usize,
        text: String,
        selection_start: usize,
        selection_end: usize,
    },
    InsertText {
        text: String,
    },
    TypeChar {
        ch: String,
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
        config: JsonCommentConfig,
    },
    ApplyTextEdits {
        edits: Vec<JsonTextEditSpec>,
    },
    ApplySnippet {
        start: usize,
        end: usize,
        snippet: String,
        #[serde(default)]
        additional_edits: Vec<JsonTextEditSpec>,
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
        options: JsonSearchOptions,
    },
    ReplaceAll {
        query: String,
        replacement: String,
        #[serde(default)]
        options: JsonSearchOptions,
    },
}

impl JsonEditCommandInput {
    fn try_into_core(self) -> Result<EditCommand, String> {
        Ok(match self {
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
            Self::ReplaceCoalescingUndo {
                start,
                length,
                text,
            } => EditCommand::ReplaceCoalescingUndo {
                start,
                length,
                text,
            },
            Self::ReplaceCoalescingUndoWithSelection {
                start,
                length,
                text,
                selection_start,
                selection_end,
            } => EditCommand::ReplaceCoalescingUndoWithSelection {
                start,
                length,
                text,
                selection_start,
                selection_end,
            },
            Self::InsertText { text } => EditCommand::InsertText { text },
            Self::TypeChar { ch } => EditCommand::TypeChar {
                ch: single_char(&ch, "ch")?,
            },
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
                config: config.into_core(),
            },
            Self::ApplyTextEdits { edits } => EditCommand::ApplyTextEdits {
                edits: edits.into_iter().map(Into::into).collect(),
            },
            Self::ApplySnippet {
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
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum JsonCursorCommandInput {
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
        start: JsonPosition,
        end: JsonPosition,
    },
    ExtendSelection {
        to: JsonPosition,
    },
    ClearSelection,
    SetSelections {
        selections: Vec<JsonSelection>,
        primary_index: usize,
    },
    ClearSecondarySelections,
    SetRectSelection {
        anchor: JsonPosition,
        active: JsonPosition,
    },
    SelectLine,
    SelectWord,
    ExpandSelection,
    ExpandSelectionBy {
        unit: JsonExpandSelectionUnit,
        count: usize,
        direction: JsonExpandSelectionDirection,
    },
    AddCursorAbove,
    AddCursorBelow,
    AddNextOccurrence {
        #[serde(default)]
        options: JsonSearchOptions,
    },
    AddAllOccurrences {
        #[serde(default)]
        options: JsonSearchOptions,
    },
    FindNext {
        query: String,
        #[serde(default)]
        options: JsonSearchOptions,
    },
    FindPrev {
        query: String,
        #[serde(default)]
        options: JsonSearchOptions,
    },
    SnippetNextPlaceholder,
    SnippetPrevPlaceholder,
}

impl JsonCursorCommandInput {
    fn try_into_core(self) -> Result<CursorCommand, String> {
        Ok(match self {
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
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum JsonViewCommandInput {
    SetViewportWidth { width: usize },
    SetWrapMode { mode: JsonWrapMode },
    SetWrapIndent { indent: JsonWrapIndent },
    SetTabWidth { width: usize },
    SetTabKeyBehavior { behavior: JsonTabKeyBehavior },
    SetIndentationConfig { config: JsonIndentationConfig },
    SetAutoPairsConfig { config: JsonAutoPairsConfig },
    SetAutoPairsEnabled { enabled: bool },
    SetWordBoundaryAsciiBoundaryChars { boundary_chars: String },
    ResetWordBoundaryDefaults,
    ScrollTo { line: usize },
    GetViewport { start_row: usize, count: usize },
}

impl JsonViewCommandInput {
    fn try_into_core(self) -> Result<ViewCommand, String> {
        Ok(match self {
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
                config: config.into_core(),
            },
            Self::SetAutoPairsConfig { config } => ViewCommand::SetAutoPairsConfig {
                config: config.try_into_core()?,
            },
            Self::SetAutoPairsEnabled { enabled } => ViewCommand::SetAutoPairsEnabled { enabled },
            Self::SetWordBoundaryAsciiBoundaryChars { boundary_chars } => {
                ViewCommand::SetWordBoundaryAsciiBoundaryChars { boundary_chars }
            }
            Self::ResetWordBoundaryDefaults => ViewCommand::ResetWordBoundaryDefaults,
            Self::ScrollTo { line } => ViewCommand::ScrollTo { line },
            Self::GetViewport { start_row, count } => ViewCommand::GetViewport { start_row, count },
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum JsonStyleCommandInput {
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
    UpdateBracketMatchHighlights,
    ClearBracketMatchHighlights,
}

impl JsonStyleCommandInput {
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
            Self::UpdateBracketMatchHighlights => StyleCommand::UpdateBracketMatchHighlights,
            Self::ClearBracketMatchHighlights => StyleCommand::ClearBracketMatchHighlights,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JsonSelectionDirection {
    Forward,
    Backward,
}

impl From<JsonSelectionDirection> for SelectionDirection {
    fn from(value: JsonSelectionDirection) -> Self {
        match value {
            JsonSelectionDirection::Forward => SelectionDirection::Forward,
            JsonSelectionDirection::Backward => SelectionDirection::Backward,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonSelection {
    start: JsonPosition,
    end: JsonPosition,
    direction: JsonSelectionDirection,
}

impl From<JsonSelection> for Selection {
    fn from(value: JsonSelection) -> Self {
        Selection {
            start: value.start.into(),
            end: value.end.into(),
            direction: value.direction.into(),
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
struct JsonPosition {
    line: usize,
    column: usize,
}

impl From<JsonPosition> for Position {
    fn from(value: JsonPosition) -> Self {
        Position {
            line: value.line,
            column: value.column,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonTextEditSpec {
    start: usize,
    end: usize,
    text: String,
}

impl From<JsonTextEditSpec> for TextEditSpec {
    fn from(value: JsonTextEditSpec) -> Self {
        TextEditSpec {
            start: value.start,
            end: value.end,
            text: value.text,
        }
    }
}

fn default_case_sensitive() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize)]
struct JsonSearchOptions {
    #[serde(default = "default_case_sensitive")]
    case_sensitive: bool,
    #[serde(default)]
    whole_word: bool,
    #[serde(default)]
    regex: bool,
}

impl Default for JsonSearchOptions {
    fn default() -> Self {
        Self {
            case_sensitive: true,
            whole_word: false,
            regex: false,
        }
    }
}

impl From<JsonSearchOptions> for SearchOptions {
    fn from(value: JsonSearchOptions) -> Self {
        SearchOptions {
            case_sensitive: value.case_sensitive,
            whole_word: value.whole_word,
            regex: value.regex,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonCommentConfig {
    line: Option<String>,
    block_start: Option<String>,
    block_end: Option<String>,
}

impl JsonCommentConfig {
    fn into_core(self) -> editor_core::CommentConfig {
        editor_core::CommentConfig {
            line: self.line,
            block_start: self.block_start,
            block_end: self.block_end,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JsonTabKeyBehavior {
    Tab,
    Spaces,
}

impl From<JsonTabKeyBehavior> for TabKeyBehavior {
    fn from(value: JsonTabKeyBehavior) -> Self {
        match value {
            JsonTabKeyBehavior::Tab => TabKeyBehavior::Tab,
            JsonTabKeyBehavior::Spaces => TabKeyBehavior::Spaces,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JsonWrapMode {
    None,
    Char,
    Word,
}

impl From<JsonWrapMode> for WrapMode {
    fn from(value: JsonWrapMode) -> Self {
        match value {
            JsonWrapMode::None => WrapMode::None,
            JsonWrapMode::Char => WrapMode::Char,
            JsonWrapMode::Word => WrapMode::Word,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum JsonWrapIndent {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<JsonWrapIndent> for WrapIndent {
    fn from(value: JsonWrapIndent) -> Self {
        match value {
            JsonWrapIndent::None => WrapIndent::None,
            JsonWrapIndent::SameAsLineIndent => WrapIndent::SameAsLineIndent,
            JsonWrapIndent::FixedCells { cells } => WrapIndent::FixedCells(cells),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum JsonIndentStyle {
    Tabs,
    Spaces { width: u8 },
}

impl From<JsonIndentStyle> for IndentStyle {
    fn from(value: JsonIndentStyle) -> Self {
        match value {
            JsonIndentStyle::Tabs => IndentStyle::Tabs,
            JsonIndentStyle::Spaces { width } => IndentStyle::Spaces(width.max(1)),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonIndentationConfig {
    #[serde(default)]
    style: Option<JsonIndentStyle>,
    #[serde(default)]
    indent_triggers: Option<Vec<String>>,
    #[serde(default)]
    outdent_triggers: Option<Vec<String>>,
}

impl JsonIndentationConfig {
    fn into_core(self) -> IndentationConfig {
        let mut cfg = IndentationConfig::default();

        if let Some(style) = self.style {
            cfg.style = style.into();
        }
        if let Some(triggers) = self.indent_triggers {
            cfg.indent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }
        if let Some(triggers) = self.outdent_triggers {
            cfg.outdent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }

        cfg
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonAutoPair {
    open: String,
    close: String,
}

impl JsonAutoPair {
    fn try_into_core(self) -> Result<AutoPair, String> {
        Ok(AutoPair {
            open: single_char(&self.open, "auto pair open")?,
            close: single_char(&self.close, "auto pair close")?,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
struct JsonAutoPairsConfig {
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    pairs: Option<Vec<JsonAutoPair>>,
    #[serde(default)]
    wrap_selection: Option<bool>,
    #[serde(default)]
    skip_over_closing: Option<bool>,
    #[serde(default)]
    delete_pair: Option<bool>,
}

impl JsonAutoPairsConfig {
    fn try_into_core(self) -> Result<AutoPairsConfig, String> {
        let mut cfg = AutoPairsConfig::default();
        if let Some(enabled) = self.enabled {
            cfg.enabled = enabled;
        }
        if let Some(pairs) = self.pairs {
            cfg.pairs = pairs
                .into_iter()
                .map(JsonAutoPair::try_into_core)
                .collect::<Result<Vec<_>, _>>()?;
        }
        if let Some(wrap_selection) = self.wrap_selection {
            cfg.wrap_selection = wrap_selection;
        }
        if let Some(skip_over_closing) = self.skip_over_closing {
            cfg.skip_over_closing = skip_over_closing;
        }
        if let Some(delete_pair) = self.delete_pair {
            cfg.delete_pair = delete_pair;
        }
        Ok(cfg)
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JsonExpandSelectionUnit {
    Character,
    Word,
    Line,
}

impl From<JsonExpandSelectionUnit> for ExpandSelectionUnit {
    fn from(value: JsonExpandSelectionUnit) -> Self {
        match value {
            JsonExpandSelectionUnit::Character => ExpandSelectionUnit::Character,
            JsonExpandSelectionUnit::Word => ExpandSelectionUnit::Word,
            JsonExpandSelectionUnit::Line => ExpandSelectionUnit::Line,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JsonExpandSelectionDirection {
    Backward,
    Forward,
}

impl From<JsonExpandSelectionDirection> for ExpandSelectionDirection {
    fn from(value: JsonExpandSelectionDirection) -> Self {
        match value {
            JsonExpandSelectionDirection::Backward => ExpandSelectionDirection::Backward,
            JsonExpandSelectionDirection::Forward => ExpandSelectionDirection::Forward,
        }
    }
}

fn single_char(value: &str, field_name: &str) -> Result<char, String> {
    let mut chars = value.chars();
    let Some(ch) = chars.next() else {
        return Err(format!("{field_name} must be exactly one character"));
    };
    if chars.next().is_some() {
        return Err(format!("{field_name} must be exactly one character"));
    }
    Ok(ch)
}

fn value_position(pos: Position) -> Value {
    json!({ "line": pos.line, "column": pos.column })
}

fn value_headless_grid(grid: &HeadlessGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_headless_line).collect::<Vec<_>>(),
    })
}

fn value_headless_line(line: &HeadlessLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "is_wrapped_part": line.is_wrapped_part,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "segment_x_start_cells": line.segment_x_start_cells,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
        "cells": line.cells.iter().map(value_cell).collect::<Vec<_>>(),
    })
}

fn value_cell(cell: &Cell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
    })
}
