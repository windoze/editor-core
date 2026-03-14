use std::fs;
use std::path::Path;

#[test]
fn devtools_toggle_permission_is_present_in_default_capability() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("capabilities/default.json");
    let src = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));

    let json: serde_json::Value =
        serde_json::from_str(&src).expect("capabilities/default.json must be valid json");

    let perms = json
        .get("permissions")
        .and_then(|v| v.as_array())
        .expect("capabilities/default.json must contain a `permissions` array");

    let perms = perms.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>();

    // `Cmd+Opt+I` (devtools toggle) triggers `webview.internal_toggle_devtools`, which requires
    // `core:webview:allow-internal-toggle-devtools` (included in `core:webview:default` and
    // transitively in `core:default`).
    assert!(
        perms.iter().any(|p| {
            *p == "core:default"
                || *p == "core:webview:default"
                || *p == "core:webview:allow-internal-toggle-devtools"
        }),
        "expected a permission that enables devtools toggle; got: {perms:?}"
    );
}

