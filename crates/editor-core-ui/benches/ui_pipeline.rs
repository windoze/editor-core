use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};
use editor_core::{Command, CommandExecutor, EditCommand, EditorStateManager};
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig};
use editor_core_ui::EditorUi;
use std::collections::BTreeMap;

fn demo_rust_text(func_count: usize) -> String {
    // 目标：生成一段“真实感”较强的 Rust 文本，使 Tree-sitter 高亮/折叠有足够工作量。
    // 同时避免极端超长行，降低 wrap/layout 的噪声。
    let mut out = String::with_capacity(func_count * 200);
    out.push_str("// editor-core-ui pipeline benchmark fixture\n");
    out.push_str("use std::fmt;\n\n");
    out.push_str("pub struct Demo {\n    pub value: usize,\n}\n\n");
    out.push_str("impl Demo {\n    pub fn new(v: usize) -> Self { Self { value: v } }\n}\n\n");

    for i in 0..func_count {
        out.push_str(&format!("pub fn func_{i:04}() -> usize {{\n"));
        out.push_str("    let mut s = 0usize;\n");
        out.push_str("    for j in 0..64 {\n");
        out.push_str("        if j % 2 == 0 {\n");
        out.push_str("            s += j;\n");
        out.push_str("        } else {\n");
        out.push_str("            s ^= j;\n");
        out.push_str("        }\n");
        out.push_str("    }\n");
        out.push_str("    // 混入一些非 ASCII 文本，模拟真实文件（不会被 Rust grammar 捕获太多）。\n");
        out.push_str("    let _msg = \"你好，世界 😀\";\n");
        out.push_str("    s\n");
        out.push_str("}\n\n");
    }

    out
}

fn setup_editor_ui(
    text: &str,
    enable_treesitter: bool,
    viewport_width_cells: usize,
) -> EditorUi {
    let mut ui = EditorUi::new(text, viewport_width_cells);
    // 与 demo 类似的渲染参数；用于 render benchmark 时得到一致的像素工作量。
    ui.set_render_metrics(13.0, 18.0, 8.0, 8.0, 8.0);
    ui.set_viewport_px(1902, 1070, 2.0).unwrap();
    ui.set_gutter_width_cells(4).unwrap();

    if enable_treesitter {
        ui.set_treesitter_rust_default().unwrap();
    }

    ui
}

fn setup_treesitter_processor_for_rust() -> TreeSitterProcessor {
    let language: tree_sitter::Language = tree_sitter_rust::LANGUAGE.into();
    let highlights = tree_sitter_rust::HIGHLIGHTS_QUERY;

    // 为了更贴近 `editor-core-ui` 的真实路径，我们需要给每个 capture 分配一个 style id，
    // 否则 processor 会跳过 interval 生成（从而低估 char-offset 转换 + interval 排序等成本）。
    let query = tree_sitter::Query::new(&language, highlights).unwrap();
    let mut capture_styles = BTreeMap::<String, u32>::new();
    for (idx, name) in query.capture_names().iter().enumerate() {
        capture_styles.insert(name.to_string(), 0x0200_0000u32 + idx as u32);
    }

    let mut config = TreeSitterProcessorConfig::new(language, highlights.to_string())
        .with_default_rust_folds();
    config.capture_styles = capture_styles;
    TreeSitterProcessor::new(config).unwrap()
}

fn bench_editor_core_typing_demo_size(c: &mut Criterion) {
    let text = demo_rust_text(200); // ~1400 行左右
    c.bench_function("editor_core/typing_middle/demo/100_inserts", |b| {
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

fn bench_treesitter_process_incremental(c: &mut Criterion) {
    let text = demo_rust_text(200);
    c.bench_function("treesitter/process_incremental/demo/100_inserts", |b| {
        b.iter_batched(
            || {
                let mut state = EditorStateManager::new(&text, 120);
                let mut proc = setup_treesitter_processor_for_rust();
                // 初次处理（建立 parse tree + style layer）。
                state.apply_processor(&mut proc).unwrap();
                (state, proc)
            },
            |(mut state, mut proc)| {
                let mut offset = state.editor().char_count() / 2;
                for _ in 0..100 {
                    state
                        .execute(Command::Edit(EditCommand::Insert {
                            offset,
                            text: "x".to_string(),
                        }))
                        .unwrap();
                    offset += 1;
                    state.apply_processor(&mut proc).unwrap();
                }
                black_box(state.editor().char_count());
            },
            BatchSize::LargeInput,
        )
    });
}

fn bench_ui_insert_text(c: &mut Criterion) {
    let text = demo_rust_text(200);

    c.bench_function("editor_core_ui/insert_text/demo/100_inserts/no_processors", |b| {
        b.iter_batched(
            || setup_editor_ui(&text, false, 120),
            |mut ui| {
                for _ in 0..100 {
                    ui.insert_text("x").unwrap();
                }
                black_box(ui.text().len());
            },
            BatchSize::LargeInput,
        )
    });

    c.bench_function("editor_core_ui/insert_text/demo/100_inserts/treesitter", |b| {
        b.iter_batched(
            || setup_editor_ui(&text, true, 120),
            |mut ui| {
                for _ in 0..100 {
                    ui.insert_text("x").unwrap();
                }
                black_box(ui.text().len());
            },
            BatchSize::LargeInput,
        )
    });
}

fn bench_ui_render_rgba_visible(c: &mut Criterion) {
    let text = demo_rust_text(200);

    c.bench_function("editor_core_ui/render_rgba_visible/demo/1_frame/no_processors", |b| {
        b.iter_batched(
            || {
                let ui = setup_editor_ui(&text, false, 120);
                let out = vec![0u8; ui.required_rgba_len()];
                (ui, out)
            },
            |(mut ui, mut out)| {
                let n = ui.render_rgba_visible_into(out.as_mut_slice()).unwrap();
                black_box(n);
                black_box(out[0]);
            },
            BatchSize::LargeInput,
        )
    });

    c.bench_function("editor_core_ui/render_rgba_visible/demo/1_frame/treesitter", |b| {
        b.iter_batched(
            || {
                let ui = setup_editor_ui(&text, true, 120);
                let out = vec![0u8; ui.required_rgba_len()];
                (ui, out)
            },
            |(mut ui, mut out)| {
                let n = ui.render_rgba_visible_into(out.as_mut_slice()).unwrap();
                black_box(n);
                black_box(out[0]);
            },
            BatchSize::LargeInput,
        )
    });
}

fn bench_ui_typing_and_render(c: &mut Criterion) {
    let text = demo_rust_text(200);

    c.bench_function(
        "editor_core_ui/typing+render_rgba_visible/demo/100_inserts/no_processors",
        |b| {
            b.iter_batched(
                || {
                    let ui = setup_editor_ui(&text, false, 120);
                    let out = vec![0u8; ui.required_rgba_len()];
                    (ui, out)
                },
                |(mut ui, mut out)| {
                    for _ in 0..100 {
                        ui.insert_text("x").unwrap();
                        let n = ui.render_rgba_visible_into(out.as_mut_slice()).unwrap();
                        black_box(n);
                    }
                    black_box(out[0]);
                },
                BatchSize::LargeInput,
            )
        },
    );

    c.bench_function(
        "editor_core_ui/typing+render_rgba_visible/demo/100_inserts/treesitter",
        |b| {
            b.iter_batched(
                || {
                    let ui = setup_editor_ui(&text, true, 120);
                    let out = vec![0u8; ui.required_rgba_len()];
                    (ui, out)
                },
                |(mut ui, mut out)| {
                    for _ in 0..100 {
                        ui.insert_text("x").unwrap();
                        let n = ui.render_rgba_visible_into(out.as_mut_slice()).unwrap();
                        black_box(n);
                    }
                    black_box(out[0]);
                },
                BatchSize::LargeInput,
            )
        },
    );
}

criterion_group!(
    benches,
    bench_editor_core_typing_demo_size,
    bench_treesitter_process_incremental,
    bench_ui_insert_text,
    bench_ui_render_rgba_visible,
    bench_ui_typing_and_render
);
criterion_main!(benches);
