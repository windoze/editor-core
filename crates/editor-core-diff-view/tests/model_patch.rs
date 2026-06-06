use editor_core_diff::LineDiffConfig;
use editor_core_diff_view::{AlignUnit, DiffModel};

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn assert_patch_model_matches_before_after(before: &str, after: &str, patch: &str) {
    let from_pair = DiffModel::from_before_after(before, after, config(0));
    let from_patch = DiffModel::from_file_and_patch(before, patch).expect("patch applies");

    assert_eq!(from_patch, from_pair);
}

#[test]
fn file_and_patch_reduces_to_before_after_model() {
    let before = "a\nold one\nold two\nz\n";
    let after = "a\nnew\nz\n";
    let patch = "--- a/file\n+++ b/file\n@@ -1,4 +1,3 @@\n a\n-old one\n-old two\n+new\n z\n";

    assert_patch_model_matches_before_after(before, after, patch);
}

#[test]
fn patch_with_limited_context_fills_unchanged_gaps() {
    let before = "a\nb\nc\nd\ne\nf\n";
    let after = "a\nb\nc\nD\ne\nf\n";
    let patch = "--- a/file\n+++ b/file\n@@ -3,3 +3,3 @@\n c\n-d\n+D\n e\n";

    let model = DiffModel::from_file_and_patch(before, patch).expect("patch applies");
    assert_eq!(
        model,
        DiffModel::from_before_after(before, after, config(0))
    );
    assert_eq!(
        model.alignment(),
        [
            AlignUnit::Context {
                sides: vec![0..3, 0..3]
            },
            AlignUnit::Replace {
                sides: vec![3..4, 3..4]
            },
            AlignUnit::Context {
                sides: vec![4..6, 4..6]
            },
        ]
    );
}

#[test]
fn empty_patch_represents_no_changes() {
    let file = "a\nb\nc\n";

    assert_patch_model_matches_before_after(file, file, "");
}

#[test]
fn no_newline_marker_preserves_final_line_without_lf() {
    let before = "a\nold";
    let after = "a\nnew";
    let patch = "--- a/file\n+++ b/file\n@@ -2 +2 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n";

    assert_patch_model_matches_before_after(before, after, patch);
}

#[test]
fn no_newline_marker_handles_crlf_patch_record_delimiters() {
    let before = "a\r\nold";
    let after = "a\r\nnew";
    let patch = "--- a/file\r\n+++ b/file\r\n@@ -2 +2 @@\r\n-old\r\n\\ No newline at end of file\r\n+new\r\n\\ No newline at end of file\r\n";

    assert_patch_model_matches_before_after(before, after, patch);
}

#[test]
fn malformed_patch_returns_error_instead_of_panicking() {
    let before = "a\nb\n";
    let patch = "--- a/file\n+++ b/file\n@@ -2,2 +2,2 @@\n b\n+new\n";

    let error = DiffModel::from_file_and_patch(before, patch).expect_err("patch is malformed");

    assert!(
        error
            .to_string()
            .contains("patch ended before hunk line counts were satisfied"),
        "unexpected error: {error}"
    );
}

#[test]
fn unexpected_non_diff_text_returns_error() {
    let error = DiffModel::from_file_and_patch("a\n", "not a unified diff\n")
        .expect_err("patch is malformed");

    assert_eq!(error.line(), Some(1));
    assert!(
        error
            .message()
            .contains("unexpected content before first unified diff hunk"),
        "unexpected error: {error}"
    );
}
