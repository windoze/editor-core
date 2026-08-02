use super::*;

pub(in crate::renderer) fn pick_reasonable_monospace_typeface_with_style(
    style: FontStyle,
) -> Option<skia_safe::Typeface> {
    let mgr = FontMgr::new();

    // Keep the list small; we just need *something* that exists on the platform.
    // If none match, fall back to the system default.
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["Menlo", "SF Mono", "Monaco", "Courier New", "Courier"]
    } else if cfg!(target_os = "windows") {
        &["Consolas", "Cascadia Mono", "Courier New"]
    } else {
        &[
            "DejaVu Sans Mono",
            "Noto Sans Mono",
            "Liberation Mono",
            "Monospace",
        ]
    };

    for name in candidates {
        if let Some(tf) = mgr.match_family_style(name, style) {
            return Some(tf);
        }
    }

    mgr.legacy_make_typeface(None, style)
}
