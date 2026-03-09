use editor_core_dist::{FfiDistManifest, FfiDistOptions, LinkMode, package_ffi_dist};
use std::fs;

#[test]
fn packages_headers_and_libs_into_stable_layout() {
    let temp = tempfile::tempdir().expect("tempdir");
    let repo_root = temp.path().join("repo");

    // Fake headers (source of truth: repo checkout).
    let core_header = repo_root.join("crates/editor-core-ffi/include/editor_core_ffi.h");
    let ui_header = repo_root.join("crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h");
    fs::create_dir_all(core_header.parent().unwrap()).unwrap();
    fs::create_dir_all(ui_header.parent().unwrap()).unwrap();
    fs::write(&core_header, b"/* core header */\n").unwrap();
    fs::write(&ui_header, b"/* ui header */\n").unwrap();

    // Fake cargo build output directory (host layout: target/<profile>/...).
    let profile_dir = repo_root.join("target/debug");
    fs::create_dir_all(&profile_dir).unwrap();
    fs::write(profile_dir.join("libeditor_core_ffi.a"), b"core static\n").unwrap();
    fs::write(profile_dir.join("libeditor_core_ui_ffi.a"), b"ui static\n").unwrap();
    fs::write(profile_dir.join("libeditor_core_ffi.dylib"), b"core dylib\n").unwrap();
    fs::write(profile_dir.join("libeditor_core_ui_ffi.dylib"), b"ui dylib\n").unwrap();

    let mut opts = FfiDistOptions::for_repo_root(&repo_root);
    opts.out_dir = temp.path().join("out");
    opts.profile = "debug".to_string();
    opts.target_triple = "unit-test-target".to_string();
    opts.mode = LinkMode::Both;

    let manifest = package_ffi_dist(&opts).expect("package");

    let out_root = opts.out_dir.join(&opts.target_triple).join(&opts.profile);
    assert!(out_root.join("include/editor_core_ffi.h").is_file());
    assert!(out_root.join("include/editor_core_ui_ffi.h").is_file());
    assert!(out_root.join("lib/libeditor_core_ffi.a").is_file());
    assert!(out_root.join("lib/libeditor_core_ui_ffi.a").is_file());
    assert!(out_root.join("lib/libeditor_core_ffi.dylib").is_file());
    assert!(out_root.join("lib/libeditor_core_ui_ffi.dylib").is_file());
    assert!(out_root.join("manifest.json").is_file());

    let manifest_bytes = fs::read(out_root.join("manifest.json")).unwrap();
    let parsed: FfiDistManifest = serde_json::from_slice(&manifest_bytes).unwrap();
    assert_eq!(parsed, manifest);
}

