use criterion::{BatchSize, Criterion, black_box, criterion_group, criterion_main};
use editor_core::{Command, CommandExecutor, EditCommand, EditorStateManager};
use editor_core_treesitter::{
    TreeSitterConfig, TreeSitterProcessor, load_processor_config_from_config,
};
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
        out.push_str(
            "    // 混入一些非 ASCII 文本，模拟真实文件（不会被 Rust grammar 捕获太多）。\n",
        );
        out.push_str("    let _msg = \"你好，世界 😀\";\n");
        out.push_str("    s\n");
        out.push_str("}\n\n");
    }

    out
}

fn treesitter_fixture_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../editor-core-treesitter/tests/fixtures/treesitter")
}

fn setup_editor_ui(text: &str, enable_treesitter: bool, viewport_width_cells: usize) -> EditorUi {
    let mut ui = EditorUi::new(text, viewport_width_cells);
    // 与 demo 类似的渲染参数；用于 render benchmark 时得到一致的像素工作量。
    ui.set_render_metrics(13.0, 18.0, 8.0, 8.0, 8.0);
    ui.set_viewport_px(1902, 1070, 2.0).unwrap();
    ui.set_gutter_width_cells(4).unwrap();

    if enable_treesitter {
        let root = treesitter_fixture_root();
        let registry_json = serde_json::json!({
            "schema_version": 1,
            "root_dir": root.to_string_lossy(),
            "extension_map": { "rs": "rust" },
            "languages": {
                "rust": {
                    "wasm": "rust/language.wasm",
                    "highlights": "rust/highlights.scm",
                    "folds": "rust/folds.scm",
                }
            }
        })
        .to_string();
        ui.set_treesitter_registry_json(&registry_json).unwrap();
        ui.set_treesitter_language("rust").unwrap();
    }

    ui
}

fn setup_treesitter_processor_for_rust() -> TreeSitterProcessor {
    let language_dir = treesitter_fixture_root().join("rust");
    let cfg = TreeSitterConfig::from_language_dir(&language_dir).expect("treesitter fixture rust/");
    let mut config =
        load_processor_config_from_config("rust", &cfg).expect("load processor config");

    // For realistic cost, allocate a style id for every capture in the highlights query.
    let capture_names = config.highlights_capture_names().unwrap();
    let mut capture_styles = BTreeMap::<String, u32>::new();
    for (idx, name) in capture_names.into_iter().enumerate() {
        capture_styles.insert(name, 0x0200_0000u32 + idx as u32);
    }
    config.capture_styles = capture_styles;

    TreeSitterProcessor::new(config).unwrap()
}

fn bench_editor_core_typing_demo_size(c: &mut Criterion) {
    let text = demo_rust_text(200); // ~1400 行左右
    c.bench_function("editor_core/typing_middle/demo/100_inserts", |b| {
        b.iter_batched(
            || CommandExecutor::new(&text, 120),
            |mut executor| {
                let start_offset = executor.editor().char_count() / 2;
                for offset in start_offset..start_offset + 100 {
                    executor
                        .execute(Command::Edit(EditCommand::Insert {
                            offset,
                            text: "x".to_string(),
                        }))
                        .unwrap();
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
                let start_offset = state.editor().char_count() / 2;
                for offset in start_offset..start_offset + 100 {
                    state
                        .execute(Command::Edit(EditCommand::Insert {
                            offset,
                            text: "x".to_string(),
                        }))
                        .unwrap();
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

    c.bench_function(
        "editor_core_ui/insert_text/demo/100_inserts/no_processors",
        |b| {
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
        },
    );

    c.bench_function(
        "editor_core_ui/insert_text/demo/100_inserts/treesitter",
        |b| {
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
        },
    );
}

fn bench_ui_render_rgba_visible(c: &mut Criterion) {
    let text = demo_rust_text(200);

    c.bench_function(
        "editor_core_ui/render_rgba_visible/demo/1_frame/no_processors",
        |b| {
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
        },
    );

    c.bench_function(
        "editor_core_ui/render_rgba_visible/demo/1_frame/treesitter",
        |b| {
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
        },
    );
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
