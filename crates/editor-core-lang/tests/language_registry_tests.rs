use editor_core_lang::{LanguageConfig, LanguageRegistry, LanguageRegistryError, LspLanguageConfig};
use std::fs;
use std::path::Path;

#[test]
fn default_registry_finds_rust_by_extension() {
    let reg = LanguageRegistry::default();
    let lang = reg.language_for_path(Path::new("main.rs")).expect("rust match");
    assert_eq!(lang.id.as_str(), "rust");
}

#[test]
fn default_registry_matches_exact_file_names() {
    let reg = LanguageRegistry::default();
    let lang = reg
        .language_for_path(Path::new("Cargo.toml"))
        .expect("Cargo.toml match");
    assert_eq!(lang.id.as_str(), "toml");
}

#[test]
fn register_rejects_duplicate_ids() {
    let mut reg = LanguageRegistry::new();
    reg.register(LanguageConfig::new("rust", "Rust")).unwrap();
    let err = reg
        .register(LanguageConfig::new("rust", "Rust 2"))
        .expect_err("duplicate should error");
    assert_eq!(
        err,
        LanguageRegistryError::DuplicateLanguageId("rust".to_string())
    );
}

#[test]
fn lsp_root_detection_finds_marker_in_ancestor_dir() {
    let temp_root = std::env::temp_dir()
        .join(format!("editor-core-lang-root-detect-{}", uuid_like()));
    fs::create_dir_all(&temp_root).unwrap();
    let _cleanup = CleanupDir(temp_root.clone());

    let nested = temp_root.join("a/b/c");
    fs::create_dir_all(&nested).unwrap();
    let file_path = nested.join("main.rs");
    fs::write(&file_path, "fn main() {}\n").unwrap();

    // Put a root marker at the root.
    fs::write(temp_root.join("Cargo.toml"), "[package]\nname = \"x\"\n").unwrap();

    let cfg = LspLanguageConfig {
        language_id: "rust".to_string(),
        command: "rust-analyzer".to_string(),
        args: Vec::new(),
        root_markers: vec!["Cargo.toml".to_string()],
    };

    let root = cfg.detect_root_dir(&file_path).expect("should find root");
    assert_eq!(root, temp_root);
}

fn uuid_like() -> String {
    // Avoid adding a dependency just for tests.
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("{nanos:x}")
}

struct CleanupDir(std::path::PathBuf);

impl Drop for CleanupDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

