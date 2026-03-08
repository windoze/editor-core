use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, StyleCommand, StyleLayerId, ViewCommand,
};

fn main() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();

    // Simulate typing a small expression.
    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: '(' }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: 'a' }))
        .unwrap();
    // Since the next character is already `)`, this will "skip over" it.
    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: ')' }))
        .unwrap();

    println!(
        "after typing: text={:?} cursor={:?}",
        executor.editor().get_text(),
        executor.editor().cursor_position()
    );

    // Update bracket highlights for the current caret.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    executor
        .execute(Command::Style(StyleCommand::UpdateBracketMatchHighlights))
        .unwrap();

    let highlight_count = executor
        .editor()
        .style_layers
        .get(&StyleLayerId::BRACKET_MATCHES)
        .map(|t| t.len())
        .unwrap_or(0);

    println!("bracket highlight intervals={highlight_count}");

    // Jump to the matching bracket.
    executor
        .execute(Command::Cursor(CursorCommand::MoveToMatchingBracket))
        .unwrap();
    println!(
        "after jump cursor={:?}",
        executor.editor().cursor_position()
    );
}
