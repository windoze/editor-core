use criterion::{BatchSize, Criterion, black_box, criterion_group, criterion_main};
use editor_core::{Command, CommandExecutor, EditCommand, EditorStateManager, ViewCommand};

fn large_text(line_count: usize) -> String {
    let mut out = String::with_capacity(line_count * 64);
    for i in 0..line_count {
        out.push_str(&format!(
            "{i:06} the quick brown fox jumps over the lazy dog (editor-core benchmark line)\n"
        ));
    }
    // Remove the final '\n' to avoid creating an extra trailing empty line.
    out.pop();
    out
}

fn bench_large_file_open(c: &mut Criterion) {
    let text = large_text(50_000);
    c.bench_function("large_file_open/50k_lines", |b| {
        b.iter(|| {
            let state = EditorStateManager::new(black_box(&text), 120);
            black_box(state.editor().line_count());
        })
    });
}

fn bench_typing_in_middle(c: &mut Criterion) {
    let text = large_text(50_000);
    c.bench_function("typing_middle/100_inserts", |b| {
        b.iter_batched(
            || CommandExecutor::new(&text, 120),
            |mut executor| {
                let mut offset = executor.editor().char_count() / 2;
                for _ in 0..100 {
                    executor
                        .execute(Command::Edit(EditCommand::Insert {
                            offset,
                            text: "x".to_string(),
                        }))
                        .unwrap();
                    offset += 1;
                }
                black_box(executor.editor().char_count());
            },
            BatchSize::LargeInput,
        )
    });
}

fn bench_viewport_render_small_slice(c: &mut Criterion) {
    let text = large_text(50_000);
    let mut executor = CommandExecutor::new(&text, 120);

    // Pick a row well into the file to avoid warming only the top-of-document paths.
    let start_row = 25_000;
    let count = 60;

    c.bench_function("viewport_render/60_lines", |b| {
        b.iter(|| {
            let result = executor
                .execute(Command::View(ViewCommand::GetViewport { start_row, count }))
                .unwrap();
            black_box(result);
        })
    });
}

criterion_group!(
    benches,
    bench_large_file_open,
    bench_typing_in_middle,
    bench_viewport_render_small_slice
);
criterion_main!(benches);
