use editor_core::{Command, CommandExecutor, EditCommand, ViewCommand};
use std::time::Instant;

fn large_text(line_count: usize) -> String {
    let mut out = String::with_capacity(line_count * 64);
    for i in 0..line_count {
        out.push_str(&format!(
            "{i:06} the quick brown fox jumps over the lazy dog (editor-core example)\n"
        ));
    }
    out.pop();
    out
}

fn main() {
    let text = large_text(50_000);

    let start = Instant::now();
    let mut executor = CommandExecutor::new(&text, 120);
    let open_time = start.elapsed();

    let mut offset = executor.editor().char_count() / 2;
    let start = Instant::now();
    for _ in 0..100 {
        executor
            .execute(Command::Edit(EditCommand::Insert {
                offset,
                text: "x".to_string(),
            }))
            .unwrap();
        offset += 1;
    }
    let typing_time = start.elapsed();

    let start = Instant::now();
    let result = executor
        .execute(Command::View(ViewCommand::GetViewport {
            start_row: 25_000,
            count: 60,
        }))
        .unwrap();
    let viewport_time = start.elapsed();

    let editor_core::CommandResult::Viewport(grid) = result else {
        panic!("expected CommandResult::Viewport");
    };

    println!("editor-core P1.5 性能示例（仅供本地观察）");
    println!("  打开 50k 行耗时: {:?}", open_time);
    println!("  中间 100 次插入耗时: {:?}", typing_time);
    println!(
        "  渲染 viewport(25k..25k+60) 耗时: {:?} (返回 {} 行)",
        viewport_time,
        grid.actual_line_count()
    );
}
