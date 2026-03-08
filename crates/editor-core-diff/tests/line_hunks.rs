use editor_core_diff::{diff_line_hunks, DiffLineKind, LineDiffConfig};
use pretty_assertions::assert_eq;

fn read_fixture(rel: &str) -> String {
    std::fs::read_to_string(format!("tests/fixtures/{rel}")).expect("read fixture")
}

#[test]
fn insertion_produces_add_line() {
    let before = "a\nb\n";
    let after = "a\nb\nc\n";
    let mut cfg = LineDiffConfig::default();
    cfg.context_lines = 0;
    let hunks = diff_line_hunks(before, after, cfg);
    assert_eq!(hunks.len(), 1);
    assert!(hunks[0]
        .lines
        .iter()
        .any(|l| l.kind == DiffLineKind::Add && l.text == "c\n"));
}

#[test]
fn deletion_produces_remove_line() {
    let before = "a\nb\nc\n";
    let after = "a\nb\n";
    let mut cfg = LineDiffConfig::default();
    cfg.context_lines = 0;
    let hunks = diff_line_hunks(before, after, cfg);
    assert_eq!(hunks.len(), 1);
    assert!(hunks[0]
        .lines
        .iter()
        .any(|l| l.kind == DiffLineKind::Remove && l.text == "c\n"));
}

#[test]
fn replacement_orders_remove_before_add() {
    let before = "a\nb\n";
    let after = "a\nx\n";
    let mut cfg = LineDiffConfig::default();
    cfg.context_lines = 0;
    let hunks = diff_line_hunks(before, after, cfg);
    assert_eq!(hunks.len(), 1);

    let lines = &hunks[0].lines;
    let remove_idx = lines
        .iter()
        .position(|l| l.kind == DiffLineKind::Remove && l.text == "b\n")
        .expect("remove line");
    let add_idx = lines
        .iter()
        .position(|l| l.kind == DiffLineKind::Add && l.text == "x\n")
        .expect("add line");
    assert!(remove_idx < add_idx);
}

#[test]
fn context_merges_adjacent_hunks() {
    let before = "a\nb\nc\nd\n";
    let after = "a\nx\nc\ny\n";

    let mut cfg0 = LineDiffConfig::default();
    cfg0.context_lines = 0;
    let hunks0 = diff_line_hunks(before, after, cfg0);
    assert_eq!(hunks0.len(), 2);

    let mut cfg1 = LineDiffConfig::default();
    cfg1.context_lines = 1;
    let hunks1 = diff_line_hunks(before, after, cfg1);
    assert_eq!(hunks1.len(), 1);
}

#[test]
fn fixture_smoke_test() {
    let before = read_fixture("simple_before.txt");
    let after = read_fixture("simple_after.txt");
    let hunks = diff_line_hunks(&before, &after, LineDiffConfig::default());
    assert_eq!(hunks.len(), 1);
    assert!(hunks[0].lines.iter().any(|l| l.kind == DiffLineKind::Add));
    assert!(hunks[0]
        .lines
        .iter()
        .any(|l| l.kind == DiffLineKind::Remove));
}

