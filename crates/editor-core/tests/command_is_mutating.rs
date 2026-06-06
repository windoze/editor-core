use editor_core::CommentConfig;
use editor_core::{
    AutoPairsConfig, Command, CursorCommand, EditCommand, ExpandSelectionDirection,
    ExpandSelectionUnit, IndentationConfig, Position, SearchOptions, Selection, SelectionDirection,
    StyleCommand, TabKeyBehavior, TextEditSpec, ViewCommand, WrapIndent, WrapMode,
};

fn assert_mutating(command: Command) {
    assert!(command.is_mutating(), "expected mutating: {command:?}");
}

fn assert_not_mutating(command: Command) {
    assert!(
        !command.is_mutating(),
        "expected readonly-safe: {command:?}"
    );
}

fn selection() -> Selection {
    Selection {
        start: Position::new(0, 1),
        end: Position::new(0, 3),
        direction: SelectionDirection::Forward,
    }
}

#[test]
fn every_edit_command_is_mutating() {
    let options = SearchOptions::default();
    let commands = [
        EditCommand::Insert {
            offset: 0,
            text: "a".to_string(),
        },
        EditCommand::Delete {
            start: 0,
            length: 1,
        },
        EditCommand::Replace {
            start: 0,
            length: 1,
            text: "b".to_string(),
        },
        EditCommand::ReplaceCoalescingUndo {
            start: 0,
            length: 1,
            text: "c".to_string(),
        },
        EditCommand::ReplaceCoalescingUndoWithSelection {
            start: 0,
            length: 1,
            text: "d".to_string(),
            selection_start: 1,
            selection_end: 1,
        },
        EditCommand::InsertText {
            text: "typed".to_string(),
        },
        EditCommand::TypeChar { ch: 'x' },
        EditCommand::InsertTab,
        EditCommand::InsertNewline { auto_indent: true },
        EditCommand::Indent,
        EditCommand::Outdent,
        EditCommand::DuplicateLines,
        EditCommand::DeleteLines,
        EditCommand::MoveLinesUp,
        EditCommand::MoveLinesDown,
        EditCommand::JoinLines,
        EditCommand::SplitLine,
        EditCommand::ToggleComment {
            config: CommentConfig::line("//"),
        },
        EditCommand::ApplyTextEdits {
            edits: vec![TextEditSpec {
                start: 0,
                end: 1,
                text: "z".to_string(),
            }],
        },
        EditCommand::ApplySnippet {
            start: 0,
            end: 1,
            snippet: "${1:name}".to_string(),
            additional_edits: vec![TextEditSpec {
                start: 2,
                end: 2,
                text: "tail".to_string(),
            }],
        },
        EditCommand::DeleteToPrevTabStop,
        EditCommand::DeleteGraphemeBack,
        EditCommand::DeleteGraphemeForward,
        EditCommand::DeleteWordBack,
        EditCommand::DeleteWordForward,
        EditCommand::Backspace,
        EditCommand::DeleteForward,
        EditCommand::Undo,
        EditCommand::Redo,
        EditCommand::EndUndoGroup,
        EditCommand::ReplaceCurrent {
            query: "a".to_string(),
            replacement: "b".to_string(),
            options,
        },
        EditCommand::ReplaceAll {
            query: "a".to_string(),
            replacement: "b".to_string(),
            options,
        },
    ];

    for command in commands {
        assert_mutating(Command::Edit(command));
    }
}

#[test]
fn cursor_selection_and_find_commands_are_not_mutating() {
    let options = SearchOptions::default();
    let commands = [
        CursorCommand::MoveTo { line: 0, column: 1 },
        CursorCommand::MoveBy {
            delta_line: 1,
            delta_column: -1,
        },
        CursorCommand::MoveVisualBy { delta_rows: 1 },
        CursorCommand::MoveToVisual { row: 1, x_cells: 2 },
        CursorCommand::MoveToLineStart,
        CursorCommand::MoveToLineEnd,
        CursorCommand::MoveToVisualLineStart,
        CursorCommand::MoveToVisualLineEnd,
        CursorCommand::MoveGraphemeLeft,
        CursorCommand::MoveGraphemeRight,
        CursorCommand::MoveWordLeft,
        CursorCommand::MoveWordRight,
        CursorCommand::MoveToMatchingBracket,
        CursorCommand::SnippetNextPlaceholder,
        CursorCommand::SnippetPrevPlaceholder,
        CursorCommand::SetSelection {
            start: Position::new(0, 0),
            end: Position::new(0, 2),
        },
        CursorCommand::ExtendSelection {
            to: Position::new(1, 0),
        },
        CursorCommand::ClearSelection,
        CursorCommand::SetSelections {
            selections: vec![selection()],
            primary_index: 0,
        },
        CursorCommand::ClearSecondarySelections,
        CursorCommand::SetRectSelection {
            anchor: Position::new(0, 0),
            active: Position::new(1, 2),
        },
        CursorCommand::SelectLine,
        CursorCommand::SelectWord,
        CursorCommand::ExpandSelection,
        CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Word,
            count: 1,
            direction: ExpandSelectionDirection::Forward,
        },
        CursorCommand::AddCursorAbove,
        CursorCommand::AddCursorBelow,
        CursorCommand::AddNextOccurrence { options },
        CursorCommand::AddAllOccurrences { options },
        CursorCommand::FindNext {
            query: "needle".to_string(),
            options,
        },
        CursorCommand::FindPrev {
            query: "needle".to_string(),
            options,
        },
    ];

    for command in commands {
        assert_not_mutating(Command::Cursor(command));
    }
}

#[test]
fn view_commands_classify_configuration_as_mutating_and_queries_as_readonly_safe() {
    let mutating_commands = [
        ViewCommand::SetViewportWidth { width: 80 },
        ViewCommand::SetWrapMode {
            mode: WrapMode::Word,
        },
        ViewCommand::SetWrapIndent {
            indent: WrapIndent::FixedCells(4),
        },
        ViewCommand::SetTabWidth { width: 4 },
        ViewCommand::SetTabKeyBehavior {
            behavior: TabKeyBehavior::Spaces,
        },
        ViewCommand::SetIndentationConfig {
            config: IndentationConfig::default(),
        },
        ViewCommand::SetAutoPairsConfig {
            config: AutoPairsConfig::default(),
        },
        ViewCommand::SetAutoPairsEnabled { enabled: true },
        ViewCommand::SetWordBoundaryAsciiBoundaryChars {
            boundary_chars: "-".to_string(),
        },
        ViewCommand::ResetWordBoundaryDefaults,
    ];

    for command in mutating_commands {
        assert_mutating(Command::View(command));
    }

    let readonly_safe_commands = [
        ViewCommand::ScrollTo { line: 3 },
        ViewCommand::GetViewport {
            start_row: 0,
            count: 10,
        },
    ];

    for command in readonly_safe_commands {
        assert_not_mutating(Command::View(command));
    }
}

#[test]
fn style_and_folding_commands_are_mutating() {
    let commands = [
        StyleCommand::AddStyle {
            start: 0,
            end: 1,
            style_id: 1,
        },
        StyleCommand::RemoveStyle {
            start: 0,
            end: 1,
            style_id: 1,
        },
        StyleCommand::Fold {
            start_line: 0,
            end_line: 2,
        },
        StyleCommand::Unfold { start_line: 0 },
        StyleCommand::UnfoldAll,
        StyleCommand::UpdateBracketMatchHighlights,
        StyleCommand::ClearBracketMatchHighlights,
    ];

    for command in commands {
        assert_mutating(Command::Style(command));
    }
}
