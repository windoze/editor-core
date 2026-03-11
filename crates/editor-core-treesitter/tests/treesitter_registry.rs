use editor_core_treesitter::{TreeSitterRegistry, TreeSitterRegistryError};
use std::path::PathBuf;

#[test]
fn scan_language_configs_finds_rust_fixture() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/treesitter");
    let map = TreeSitterRegistry::scan_language_configs(&root).expect("scan_language_configs");
    let rust = map.get("rust").expect("rust config");
    assert!(rust.wasm_path.ends_with("rust/language.wasm"));
    assert!(rust.highlights_path.ends_with("rust/highlights.scm"));
}

#[test]
fn registry_json_resolves_relative_paths_and_extension_mapping() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/treesitter");
    let json = serde_json::json!({
        "schema_version": 1,
        "root_dir": root.to_string_lossy(),
        "extension_map": { "rs": "rust" },
        "languages": {
            "rust": {
                "wasm": "rust/language.wasm",
                "highlights": "rust/highlights.scm",
                "folds": "rust/folds.scm",
                "indents": "rust/indents.scm",
                "tags": "rust/tags.scm",
                "injections": "rust/injections.scm",
            }
        }
    })
    .to_string();

    let registry = TreeSitterRegistry::from_json_str(&json).expect("from_json_str");
    let rust = registry.languages.get("rust").expect("rust config");
    assert_eq!(rust.wasm_path, root.join("rust/language.wasm"));
    assert_eq!(rust.highlights_path, root.join("rust/highlights.scm"));
    let expected_folds = root.join("rust/folds.scm");
    assert_eq!(rust.folds_path.as_deref(), Some(expected_folds.as_path()));
    let expected_indents = root.join("rust/indents.scm");
    assert_eq!(
        rust.indents_path.as_deref(),
        Some(expected_indents.as_path())
    );

    let language_id = registry
        .language_id_for_path(std::path::Path::new("foo.RS"))
        .expect("language_id_for_path");
    assert_eq!(language_id, "rust");
}

#[test]
fn registry_json_rejects_unknown_schema_version() {
    let json = r#"{ "schema_version": 999, "languages": {} }"#;
    let err = TreeSitterRegistry::from_json_str(json).unwrap_err();
    assert!(matches!(
        err,
        TreeSitterRegistryError::UnsupportedSchemaVersion(999)
    ));
}
