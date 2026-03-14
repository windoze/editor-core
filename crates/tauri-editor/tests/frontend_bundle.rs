use std::fs;
use std::path::Path;

#[test]
fn frontend_bundle_does_not_call_missing_update_line_element() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("ui/dist/app.js");
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
            "ui/dist/app.js calls updateLineElement(...) but does not define it"
        );
    }
}

