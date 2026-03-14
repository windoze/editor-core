use std::fs;
use std::path::Path;

#[test]
fn frontend_bundle_does_not_call_missing_update_line_element() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/editor/app.js");
    let src = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));

    // 回归保护：曾出现 `updateLineElement(...)` 的调用残留，但函数本身已被重命名/删除，
    // 导致 WebView 运行时报 `ReferenceError`，从而让输入/鼠标交互看起来“全部失效”。
    if src.contains("updateLineElement(") {
        let defined = src.contains("function updateLineElement(")
            || src.contains("const updateLineElement")
            || src.contains("let updateLineElement");
        assert!(
            defined,
            "frontend app.js calls updateLineElement(...) but does not define it"
        );
    }
}

#[test]
fn debug_hud_is_disabled_by_default_in_frontend_bundle() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/editor/app.js");
    let src = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));

    // 回归保护：debugHud 会遮挡 UI，默认应关闭，仅在 env/feature 显式开启时打开。
    assert!(
        src.contains("let debugHudEnabled = false"),
        "expected debugHudEnabled to default to false in frontend app.js"
    );
    assert!(
        !src.contains("const debugHud = (() =>"),
        "expected debugHud element not to be created unconditionally at module load"
    );
    assert!(
        src.contains("debug_hud_enabled"),
        "expected frontend to consult backend debug_hud_enabled flag"
    );
}

#[test]
fn folding_gutter_is_separate_and_vscode_style() {
    let app_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/editor/app.js");
    let css_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/style.css");
    let app = fs::read_to_string(&app_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", app_path.display()));
    let css = fs::read_to_string(&css_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", css_path.display()));

    // 回归保护：折叠 gutter 应位于行号与正文之间（单独一列），并使用 VS Code 风格的 chevron。
    assert!(
        app.contains("gutter-line-number") && app.contains("gutter-folding"),
        "expected frontend app.js to render separate line-number + folding gutters"
    );
    assert!(
        app.contains("rowEl.replaceChildren(lineNumberGutterEl, foldingGutterEl, lineEl)"),
        "expected folding gutter to be inserted between line numbers and text"
    );
    assert!(
        css.contains(".gutter-folding") && css.contains(".fold-toggle.foldable::before"),
        "expected frontend style.css to contain folding gutter + chevron styles"
    );
}
