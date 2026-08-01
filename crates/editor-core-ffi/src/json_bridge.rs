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

pub(crate) fn default_case_sensitive() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub(crate) struct FfiSearchOptions {
    #[serde(default = "default_case_sensitive")]
    case_sensitive: bool,
    #[serde(default)]
    whole_word: bool,
    #[serde(default)]
    regex: bool,
}

impl Default for FfiSearchOptions {
    fn default() -> Self {
        Self {
            case_sensitive: true,
            whole_word: false,
            regex: false,
        }
    }
}

impl From<FfiSearchOptions> for SearchOptions {
    fn from(value: FfiSearchOptions) -> Self {
        SearchOptions {
            case_sensitive: value.case_sensitive,
            whole_word: value.whole_word,
            regex: value.regex,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiCommentConfig {
    line: Option<String>,
    block_start: Option<String>,
    block_end: Option<String>,
}

impl From<FfiCommentConfig> for editor_core::CommentConfig {
    fn from(value: FfiCommentConfig) -> Self {
        editor_core::CommentConfig {
            line: value.line,
            block_start: value.block_start,
            block_end: value.block_end,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiTabKeyBehavior {
    Tab,
    Spaces,
}

impl From<FfiTabKeyBehavior> for TabKeyBehavior {
    fn from(value: FfiTabKeyBehavior) -> Self {
        match value {
            FfiTabKeyBehavior::Tab => TabKeyBehavior::Tab,
            FfiTabKeyBehavior::Spaces => TabKeyBehavior::Spaces,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiWrapMode {
    None,
    Char,
    Word,
}

impl From<FfiWrapMode> for WrapMode {
    fn from(value: FfiWrapMode) -> Self {
        match value {
            FfiWrapMode::None => WrapMode::None,
            FfiWrapMode::Char => WrapMode::Char,
            FfiWrapMode::Word => WrapMode::Word,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiWrapIndent {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<FfiWrapIndent> for WrapIndent {
    fn from(value: FfiWrapIndent) -> Self {
        match value {
            FfiWrapIndent::None => WrapIndent::None,
            FfiWrapIndent::SameAsLineIndent => WrapIndent::SameAsLineIndent,
            FfiWrapIndent::FixedCells { cells } => WrapIndent::FixedCells(cells),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiIndentStyle {
    Tabs,
    Spaces { width: u8 },
}

impl From<FfiIndentStyle> for IndentStyle {
    fn from(value: FfiIndentStyle) -> Self {
        match value {
            FfiIndentStyle::Tabs => IndentStyle::Tabs,
            FfiIndentStyle::Spaces { width } => IndentStyle::Spaces(width.max(1)),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiIndentationConfig {
    #[serde(default)]
    style: Option<FfiIndentStyle>,
    #[serde(default)]
    indent_triggers: Option<Vec<String>>,
    #[serde(default)]
    outdent_triggers: Option<Vec<String>>,
}

impl From<FfiIndentationConfig> for IndentationConfig {
    fn from(value: FfiIndentationConfig) -> Self {
        let mut cfg = IndentationConfig::default();

        if let Some(style) = value.style {
            cfg.style = style.into();
        }

        if let Some(triggers) = value.indent_triggers {
            cfg.indent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }

        if let Some(triggers) = value.outdent_triggers {
            cfg.outdent_triggers = triggers
                .into_iter()
                .filter_map(|s| s.chars().next())
                .collect();
        }

        cfg
    }
}

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
    fn into_core(self) -> Command {
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

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiIntervalInput {
    start: usize,
    end: usize,
    style_id: u32,
}

impl From<FfiIntervalInput> for Interval {
    fn from(value: FfiIntervalInput) -> Self {
        Interval::new(value.start, value.end, value.style_id)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiFoldRegionInput {
    start_line: usize,
    end_line: usize,
    #[serde(default)]
    is_collapsed: bool,
    #[serde(default = "default_fold_placeholder")]
    placeholder: String,
}

pub(crate) fn default_fold_placeholder() -> String {
    "[...]".to_string()
}

impl From<FfiFoldRegionInput> for FoldRegion {
    fn from(value: FfiFoldRegionInput) -> Self {
        FoldRegion {
            start_line: value.start_line,
            end_line: value.end_line,
            is_collapsed: value.is_collapsed,
            placeholder: value.placeholder,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiDiagnosticSeverity {
    Error,
    Warning,
    Information,
    Hint,
}

impl From<FfiDiagnosticSeverity> for DiagnosticSeverity {
    fn from(value: FfiDiagnosticSeverity) -> Self {
        match value {
            FfiDiagnosticSeverity::Error => DiagnosticSeverity::Error,
            FfiDiagnosticSeverity::Warning => DiagnosticSeverity::Warning,
            FfiDiagnosticSeverity::Information => DiagnosticSeverity::Information,
            FfiDiagnosticSeverity::Hint => DiagnosticSeverity::Hint,
        }
    }
}

pub(crate) fn diagnostic_severity_to_str(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Information => "information",
        DiagnosticSeverity::Hint => "hint",
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDiagnosticInput {
    range: FfiOffsetRange,
    severity: Option<FfiDiagnosticSeverity>,
    code: Option<String>,
    source: Option<String>,
    message: String,
    related_information_json: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDiagnosticInput> for Diagnostic {
    fn from(value: FfiDiagnosticInput) -> Self {
        Diagnostic {
            range: DiagnosticRange::new(value.range.start, value.range.end),
            severity: value.severity.map(Into::into),
            code: value.code,
            source: value.source,
            message: value.message,
            related_information_json: value.related_information_json,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiDecorationPlacement {
    Before,
    After,
    AboveLine,
}

impl From<FfiDecorationPlacement> for DecorationPlacement {
    fn from(value: FfiDecorationPlacement) -> Self {
        match value {
            FfiDecorationPlacement::Before => DecorationPlacement::Before,
            FfiDecorationPlacement::After => DecorationPlacement::After,
            FfiDecorationPlacement::AboveLine => DecorationPlacement::AboveLine,
        }
    }
}

pub(crate) fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub(crate) enum FfiDecorationKind {
    InlayHint,
    CodeLens,
    DocumentLink,
    Highlight,
    Custom(u32),
}

impl From<FfiDecorationKind> for DecorationKind {
    fn from(value: FfiDecorationKind) -> Self {
        match value {
            FfiDecorationKind::InlayHint => DecorationKind::InlayHint,
            FfiDecorationKind::CodeLens => DecorationKind::CodeLens,
            FfiDecorationKind::DocumentLink => DecorationKind::DocumentLink,
            FfiDecorationKind::Highlight => DecorationKind::Highlight,
            FfiDecorationKind::Custom(v) => DecorationKind::Custom(v),
        }
    }
}

pub(crate) fn decoration_kind_to_json(value: DecorationKind) -> Value {
    match value {
        DecorationKind::InlayHint => json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => json!({ "kind": "document_link" }),
        DecorationKind::Highlight => json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDecorationInput {
    range: FfiOffsetRange,
    placement: FfiDecorationPlacement,
    kind: FfiDecorationKind,
    text: Option<String>,
    #[serde(default)]
    styles: Vec<u32>,
    tooltip: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDecorationInput> for Decoration {
    fn from(value: FfiDecorationInput) -> Self {
        Decoration {
            range: DecorationRange::new(value.range.start, value.range.end),
            placement: value.placement.into(),
            kind: value.kind.into(),
            text: value.text,
            styles: value.styles,
            tooltip: value.tooltip,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub(crate) enum FfiSymbolKind {
    File,
    Module,
    Namespace,
    Package,
    Class,
    Method,
    Property,
    Field,
    Constructor,
    Enum,
    Interface,
    Function,
    Variable,
    Constant,
    String,
    Number,
    Boolean,
    Array,
    Object,
    Key,
    Null,
    EnumMember,
    Struct,
    Event,
    Operator,
    TypeParameter,
    Custom(u32),
}

impl From<FfiSymbolKind> for SymbolKind {
    fn from(value: FfiSymbolKind) -> Self {
        match value {
            FfiSymbolKind::File => SymbolKind::File,
            FfiSymbolKind::Module => SymbolKind::Module,
            FfiSymbolKind::Namespace => SymbolKind::Namespace,
            FfiSymbolKind::Package => SymbolKind::Package,
            FfiSymbolKind::Class => SymbolKind::Class,
            FfiSymbolKind::Method => SymbolKind::Method,
            FfiSymbolKind::Property => SymbolKind::Property,
            FfiSymbolKind::Field => SymbolKind::Field,
            FfiSymbolKind::Constructor => SymbolKind::Constructor,
            FfiSymbolKind::Enum => SymbolKind::Enum,
            FfiSymbolKind::Interface => SymbolKind::Interface,
            FfiSymbolKind::Function => SymbolKind::Function,
            FfiSymbolKind::Variable => SymbolKind::Variable,
            FfiSymbolKind::Constant => SymbolKind::Constant,
            FfiSymbolKind::String => SymbolKind::String,
            FfiSymbolKind::Number => SymbolKind::Number,
            FfiSymbolKind::Boolean => SymbolKind::Boolean,
            FfiSymbolKind::Array => SymbolKind::Array,
            FfiSymbolKind::Object => SymbolKind::Object,
            FfiSymbolKind::Key => SymbolKind::Key,
            FfiSymbolKind::Null => SymbolKind::Null,
            FfiSymbolKind::EnumMember => SymbolKind::EnumMember,
            FfiSymbolKind::Struct => SymbolKind::Struct,
            FfiSymbolKind::Event => SymbolKind::Event,
            FfiSymbolKind::Operator => SymbolKind::Operator,
            FfiSymbolKind::TypeParameter => SymbolKind::TypeParameter,
            FfiSymbolKind::Custom(v) => SymbolKind::Custom(v),
        }
    }
}

pub(crate) fn symbol_kind_to_json(value: SymbolKind) -> Value {
    match value {
        SymbolKind::File => json!({ "kind": "file" }),
        SymbolKind::Module => json!({ "kind": "module" }),
        SymbolKind::Namespace => json!({ "kind": "namespace" }),
        SymbolKind::Package => json!({ "kind": "package" }),
        SymbolKind::Class => json!({ "kind": "class" }),
        SymbolKind::Method => json!({ "kind": "method" }),
        SymbolKind::Property => json!({ "kind": "property" }),
        SymbolKind::Field => json!({ "kind": "field" }),
        SymbolKind::Constructor => json!({ "kind": "constructor" }),
        SymbolKind::Enum => json!({ "kind": "enum" }),
        SymbolKind::Interface => json!({ "kind": "interface" }),
        SymbolKind::Function => json!({ "kind": "function" }),
        SymbolKind::Variable => json!({ "kind": "variable" }),
        SymbolKind::Constant => json!({ "kind": "constant" }),
        SymbolKind::String => json!({ "kind": "string" }),
        SymbolKind::Number => json!({ "kind": "number" }),
        SymbolKind::Boolean => json!({ "kind": "boolean" }),
        SymbolKind::Array => json!({ "kind": "array" }),
        SymbolKind::Object => json!({ "kind": "object" }),
        SymbolKind::Key => json!({ "kind": "key" }),
        SymbolKind::Null => json!({ "kind": "null" }),
        SymbolKind::EnumMember => json!({ "kind": "enum_member" }),
        SymbolKind::Struct => json!({ "kind": "struct" }),
        SymbolKind::Event => json!({ "kind": "event" }),
        SymbolKind::Operator => json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiOffsetRange {
    start: usize,
    end: usize,
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

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiDocumentSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    range: FfiOffsetRange,
    selection_range: FfiOffsetRange,
    #[serde(default)]
    children: Vec<FfiDocumentSymbolInput>,
    data_json: Option<String>,
}

impl From<FfiDocumentSymbolInput> for DocumentSymbol {
    fn from(value: FfiDocumentSymbolInput) -> Self {
        DocumentSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            range: SymbolRange::new(value.range.start, value.range.end),
            selection_range: SymbolRange::new(
                value.selection_range.start,
                value.selection_range.end,
            ),
            children: value.children.into_iter().map(Into::into).collect(),
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiWorkspaceSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    location: FfiSymbolLocation,
    container_name: Option<String>,
    data_json: Option<String>,
}

impl From<FfiWorkspaceSymbolInput> for WorkspaceSymbol {
    fn from(value: FfiWorkspaceSymbolInput) -> Self {
        WorkspaceSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            location: value.location.into(),
            container_name: value.container_name,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiProcessingEditInput {
    ReplaceStyleLayer {
        layer: u32,
        intervals: Vec<FfiIntervalInput>,
    },
    ClearStyleLayer {
        layer: u32,
    },
    ReplaceFoldingRegions {
        regions: Vec<FfiFoldRegionInput>,
        #[serde(default)]
        preserve_collapsed: bool,
    },
    ClearFoldingRegions,
    ReplaceDiagnostics {
        diagnostics: Vec<FfiDiagnosticInput>,
    },
    ClearDiagnostics,
    ReplaceDecorations {
        layer: u32,
        decorations: Vec<FfiDecorationInput>,
    },
    ClearDecorations {
        layer: u32,
    },
    ReplaceDocumentSymbols {
        symbols: Vec<FfiDocumentSymbolInput>,
    },
    ClearDocumentSymbols,
}

impl FfiProcessingEditInput {
    fn into_core(self) -> ProcessingEdit {
        match self {
            Self::ReplaceStyleLayer { layer, intervals } => ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::new(layer),
                intervals: intervals.into_iter().map(Into::into).collect(),
            },
            Self::ClearStyleLayer { layer } => ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::new(layer),
            },
            Self::ReplaceFoldingRegions {
                regions,
                preserve_collapsed,
            } => ProcessingEdit::ReplaceFoldingRegions {
                regions: regions.into_iter().map(Into::into).collect(),
                preserve_collapsed,
            },
            Self::ClearFoldingRegions => ProcessingEdit::ClearFoldingRegions,
            Self::ReplaceDiagnostics { diagnostics } => ProcessingEdit::ReplaceDiagnostics {
                diagnostics: diagnostics.into_iter().map(Into::into).collect(),
            },
            Self::ClearDiagnostics => ProcessingEdit::ClearDiagnostics,
            Self::ReplaceDecorations { layer, decorations } => ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::new(layer),
                decorations: decorations.into_iter().map(Into::into).collect(),
            },
            Self::ClearDecorations { layer } => ProcessingEdit::ClearDecorations {
                layer: DecorationLayerId::new(layer),
            },
            Self::ReplaceDocumentSymbols { symbols } => ProcessingEdit::ReplaceDocumentSymbols {
                symbols: DocumentOutline::new(symbols.into_iter().map(Into::into).collect()),
            },
            Self::ClearDocumentSymbols => ProcessingEdit::ClearDocumentSymbols,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub(crate) enum FfiProcessingEditsInput {
    One(FfiProcessingEditInput),
    Many(Vec<FfiProcessingEditInput>),
}

impl FfiProcessingEditsInput {
    fn into_core(self) -> Vec<ProcessingEdit> {
        match self {
            Self::One(edit) => vec![edit.into_core()],
            Self::Many(edits) => edits
                .into_iter()
                .map(FfiProcessingEditInput::into_core)
                .collect(),
        }
    }
}

pub(crate) fn value_position(value: Position) -> Value {
    json!({ "line": value.line, "column": value.column })
}

pub(crate) fn value_selection(value: &Selection) -> Value {
    json!({
        "start": value_position(value.start),
        "end": value_position(value.end),
        "direction": selection_direction_to_str(value.direction)
    })
}

pub(crate) fn value_offset_range(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

pub(crate) fn value_utf16_position(value: Utf16Position) -> Value {
    json!({ "line": value.line, "character": value.character })
}

pub(crate) fn value_utf16_range(value: Utf16Range) -> Value {
    json!({
        "start": value_utf16_position(value.start),
        "end": value_utf16_position(value.end)
    })
}

pub(crate) fn value_symbol_location(value: &SymbolLocation) -> Value {
    json!({
        "uri": value.uri,
        "range": value_utf16_range(value.range)
    })
}

pub(crate) fn value_document_symbol(symbol: &DocumentSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
}

pub(crate) fn value_workspace_symbol(symbol: &WorkspaceSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "location": value_symbol_location(&symbol.location),
        "container_name": symbol.container_name,
        "data_json": symbol.data_json
    })
}

pub(crate) fn value_interval(interval: &Interval) -> Value {
    json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}

pub(crate) fn value_fold_region(region: &FoldRegion) -> Value {
    json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

pub(crate) fn value_diagnostic(diagnostic: &Diagnostic) -> Value {
    json!({
        "range": value_offset_range(diagnostic.range.start, diagnostic.range.end),
        "severity": diagnostic.severity.map(diagnostic_severity_to_str),
        "code": diagnostic.code,
        "source": diagnostic.source,
        "message": diagnostic.message,
        "related_information_json": diagnostic.related_information_json,
        "data_json": diagnostic.data_json
    })
}

pub(crate) fn value_decoration(decoration: &Decoration) -> Value {
    json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

pub(crate) fn value_processing_edit(edit: &ProcessingEdit) -> Value {
    match edit {
        ProcessingEdit::ReplaceStyleLayer { layer, intervals } => json!({
            "op": "replace_style_layer",
            "layer": layer.0,
            "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearStyleLayer { layer } => json!({
            "op": "clear_style_layer",
            "layer": layer.0
        }),
        ProcessingEdit::ReplaceFoldingRegions {
            regions,
            preserve_collapsed,
        } => json!({
            "op": "replace_folding_regions",
            "regions": regions.iter().map(value_fold_region).collect::<Vec<_>>(),
            "preserve_collapsed": preserve_collapsed,
        }),
        ProcessingEdit::ClearFoldingRegions => json!({ "op": "clear_folding_regions" }),
        ProcessingEdit::ReplaceDiagnostics { diagnostics } => json!({
            "op": "replace_diagnostics",
            "diagnostics": diagnostics.iter().map(value_diagnostic).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDiagnostics => json!({ "op": "clear_diagnostics" }),
        ProcessingEdit::ReplaceDecorations { layer, decorations } => json!({
            "op": "replace_decorations",
            "layer": layer.0,
            "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDecorations { layer } => json!({
            "op": "clear_decorations",
            "layer": layer.0,
        }),
        ProcessingEdit::ReplaceDocumentSymbols { symbols } => json!({
            "op": "replace_document_symbols",
            "symbols": symbols.symbols.iter().map(value_document_symbol).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDocumentSymbols => json!({ "op": "clear_document_symbols" }),
    }
}

pub(crate) fn value_text_delta(delta: &editor_core::TextDelta) -> Value {
    json!({
        "before_char_count": delta.before_char_count,
        "after_char_count": delta.after_char_count,
        "undo_group_id": delta.undo_group_id,
        "edits": delta.edits.iter().map(|edit| json!({
            "start": edit.start,
            "deleted_text": edit.deleted_text,
            "inserted_text": edit.inserted_text,
        })).collect::<Vec<_>>()
    })
}

pub(crate) fn value_headless_cell(cell: &Cell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
    })
}

pub(crate) fn value_headless_line(line: &HeadlessLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "is_wrapped_part": line.is_wrapped_part,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "segment_x_start_cells": line.segment_x_start_cells,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
        "cells": line.cells.iter().map(value_headless_cell).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_headless_grid(grid: &HeadlessGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_headless_line).collect::<Vec<_>>()
    })
}

pub(crate) fn value_minimap_line(line: &MinimapLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "total_cells": line.total_cells,
        "non_whitespace_cells": line.non_whitespace_cells,
        "dominant_style": line.dominant_style,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
    })
}

pub(crate) fn value_minimap_grid(grid: &MinimapGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_minimap_line).collect::<Vec<_>>()
    })
}

pub(crate) fn value_composed_cell_source(source: ComposedCellSource) -> Value {
    match source {
        ComposedCellSource::Document { offset } => json!({ "kind": "document", "offset": offset }),
        ComposedCellSource::Virtual { anchor_offset } => {
            json!({ "kind": "virtual", "anchor_offset": anchor_offset })
        }
    }
}

pub(crate) fn value_composed_cell(cell: &ComposedCell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
        "source": value_composed_cell_source(cell.source),
    })
}

pub(crate) fn value_composed_line_kind(kind: ComposedLineKind) -> Value {
    match kind {
        ComposedLineKind::Document {
            logical_line,
            visual_in_logical,
        } => json!({
            "kind": "document",
            "logical_line": logical_line,
            "visual_in_logical": visual_in_logical,
        }),
        ComposedLineKind::VirtualAboveLine { logical_line } => {
            json!({ "kind": "virtual_above_line", "logical_line": logical_line })
        }
    }
}

pub(crate) fn value_composed_line(line: &ComposedLine) -> Value {
    json!({
        "kind": value_composed_line_kind(line.kind),
        "cells": line.cells.iter().map(value_composed_cell).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_composed_grid(grid: &ComposedGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_composed_line).collect::<Vec<_>>(),
    })
}

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

pub(crate) fn value_document_state(state: &DocumentState) -> Value {
    json!({
        "line_count": state.line_count,
        "char_count": state.char_count,
        "byte_count": state.byte_count,
        "is_modified": state.is_modified,
        "version": state.version,
    })
}

pub(crate) fn value_cursor_state(state: &CursorState) -> Value {
    json!({
        "position": value_position(state.position),
        "offset": state.offset,
        "multi_cursors": state.multi_cursors.iter().map(|p| value_position(*p)).collect::<Vec<_>>(),
        "selection": state.selection.as_ref().map(value_selection),
        "selections": state.selections.iter().map(value_selection).collect::<Vec<_>>(),
        "primary_selection_index": state.primary_selection_index,
    })
}

pub(crate) fn value_range_state(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

pub(crate) fn value_viewport_state(state: &ViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
        "total_visual_lines": state.total_visual_lines,
    })
}

pub(crate) fn value_undo_redo_state(state: &UndoRedoState) -> Value {
    json!({
        "can_undo": state.can_undo,
        "can_redo": state.can_redo,
        "undo_depth": state.undo_depth,
        "redo_depth": state.redo_depth,
        "current_change_group": state.current_change_group,
    })
}

pub(crate) fn value_folding_state(state: &FoldingState) -> Value {
    json!({
        "regions": state.regions.iter().map(value_fold_region).collect::<Vec<_>>(),
        "collapsed_line_count": state.collapsed_line_count,
        "visible_logical_lines": state.visible_logical_lines,
        "total_visual_lines": state.total_visual_lines,
    })
}

pub(crate) fn value_diagnostics_state(state: &DiagnosticsState) -> Value {
    json!({ "diagnostics_count": state.diagnostics_count })
}

pub(crate) fn value_decorations_state(state: &DecorationsState) -> Value {
    json!({
        "layer_count": state.layer_count,
        "decoration_count": state.decoration_count,
    })
}

pub(crate) fn value_style_state(state: &StyleState) -> Value {
    json!({ "style_count": state.style_count })
}

pub(crate) fn value_editor_state(state: &EditorState) -> Value {
    json!({
        "document": value_document_state(&state.document),
        "cursor": value_cursor_state(&state.cursor),
        "viewport": value_viewport_state(&state.viewport),
        "undo_redo": value_undo_redo_state(&state.undo_redo),
        "folding": value_folding_state(&state.folding),
        "diagnostics": value_diagnostics_state(&state.diagnostics),
        "decorations": value_decorations_state(&state.decorations),
        "style": value_style_state(&state.style),
    })
}

pub(crate) fn value_workspace_search_result(item: &WorkspaceSearchResult) -> Value {
    json!({
        "buffer_id": item.id.get(),
        "uri": item.uri,
        "matches": item.matches.iter().map(|m| value_search_match(*m)).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_search_match(m: SearchMatch) -> Value {
    json!({ "start": m.start, "end": m.end })
}

pub(crate) fn value_smooth_scroll_state(state: ViewSmoothScrollState) -> Value {
    json!({
        "top_visual_row": state.top_visual_row,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
    })
}

pub(crate) fn value_workspace_viewport_state(state: &WorkspaceViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "total_visual_lines": state.total_visual_lines,
        "smooth_scroll": value_smooth_scroll_state(state.smooth_scroll),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
    })
}

pub(crate) fn value_open_buffer_result(result: OpenBufferResult) -> Value {
    json!({
        "buffer_id": result.buffer_id.get(),
        "view_id": result.view_id.get(),
    })
}

pub(crate) fn parse_command_from_json(json_text: &str) -> Result<Command, String> {
    let input: FfiCommandInput = parse_json(json_text, "command")?;
    Ok(input.into_core())
}

pub(crate) fn parse_processing_edits(json_text: &str) -> Result<Vec<ProcessingEdit>, String> {
    let input: FfiProcessingEditsInput = parse_json(json_text, "processing edits")?;
    Ok(input.into_core())
}
