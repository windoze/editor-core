pub(in crate::renderer) fn default_font_families() -> Vec<&'static str> {
    // Keep the list fairly small and ordered by preference.
    //
    // For CJK + emoji correctness we include explicit fallbacks after the primary monospace.
    if cfg!(target_os = "macos") {
        vec![
            // Primary monospace candidates.
            "Menlo",
            "SF Mono",
            "Monaco",
            "Courier New",
            "Courier",
            // CJK fallbacks.
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            // Emoji fallback.
            "Apple Color Emoji",
        ]
    } else if cfg!(target_os = "windows") {
        vec![
            "Consolas",
            "Cascadia Mono",
            "Courier New",
            // CJK + emoji best-effort.
            "Microsoft YaHei",
            "Segoe UI Emoji",
            "Segoe UI Symbol",
        ]
    } else {
        vec![
            "DejaVu Sans Mono",
            "Noto Sans Mono",
            "Liberation Mono",
            "Monospace",
            // CJK + emoji best-effort.
            "Noto Sans CJK SC",
            "Noto Color Emoji",
            "Noto Emoji",
        ]
    }
}
