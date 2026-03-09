use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, IndentStyle, IndentationConfig,
    ViewCommand,
};

#[test]
fn insert_newline_auto_indent_increases_after_indent_trigger() {
    let mut exec = CommandExecutor::new("fn main() {", 80);
    exec.execute(Command::Cursor(CursorCommand::MoveToLineEnd))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::InsertNewline {
        auto_indent: true,
    }))
    .unwrap();
    assert_eq!(exec.editor().get_text(), "fn main() {\n    ");
}

#[test]
fn insert_newline_between_braces_inserts_blank_indented_line_and_keeps_closing_aligned() {
    let mut exec = CommandExecutor::new("{}", 80);
    exec.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 1,
    }))
    .unwrap();
    exec.execute(Command::Edit(EditCommand::InsertNewline {
        auto_indent: true,
    }))
    .unwrap();
    assert_eq!(exec.editor().get_text(), "{\n    \n}");
    assert_eq!(
        exec.editor().cursor_position(),
        editor_core::Position::new(1, 4)
    );
}

#[test]
fn indentation_config_controls_indent_unit() {
    let mut exec = CommandExecutor::new("{}", 80);
    exec.execute(Command::View(ViewCommand::SetIndentationConfig {
        config: IndentationConfig {
            style: IndentStyle::Spaces(2),
            indent_triggers: vec!['{', '[', '('],
            outdent_triggers: vec!['}', ']', ')'],
        },
    }))
    .unwrap();
    exec.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 1,
    }))
    .unwrap();
    exec.execute(Command::Edit(EditCommand::InsertNewline {
        auto_indent: true,
    }))
    .unwrap();
    assert_eq!(exec.editor().get_text(), "{\n  \n}");
    assert_eq!(
        exec.editor().cursor_position(),
        editor_core::Position::new(1, 2)
    );
}

#[test]
fn indentation_config_is_view_local_in_workspace() {
    let mut ws = editor_core::Workspace::new();
    let opened = ws.open_buffer(None, "{}", 80).unwrap();
    let v1 = opened.view_id;
    let v2 = ws.create_view(opened.buffer_id, 80).unwrap();

    ws.execute(
        v1,
        Command::View(ViewCommand::SetIndentationConfig {
            config: IndentationConfig {
                style: IndentStyle::Spaces(2),
                indent_triggers: vec!['{', '[', '('],
                outdent_triggers: vec!['}', ']', ')'],
            },
        }),
    )
    .unwrap();

    ws.execute(
        v1,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    ws.execute(
        v1,
        Command::Edit(EditCommand::InsertNewline { auto_indent: true }),
    )
    .unwrap();
    assert_eq!(ws.buffer_text(opened.buffer_id).unwrap(), "{\n  \n}");

    // Undo and perform the same edit from view2 with the default (spaces=4) config.
    ws.execute(v1, Command::Edit(EditCommand::Undo)).unwrap();
    ws.execute(
        v2,
        Command::View(ViewCommand::SetIndentationConfig {
            config: IndentationConfig::default(),
        }),
    )
    .unwrap();
    ws.execute(
        v2,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    ws.execute(
        v2,
        Command::Edit(EditCommand::InsertNewline { auto_indent: true }),
    )
    .unwrap();
    assert_eq!(ws.buffer_text(opened.buffer_id).unwrap(), "{\n    \n}");
}
