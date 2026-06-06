use editor_core_diff::LineDiffConfig;
use editor_core_diff_view::AlignUnit;
use editor_core_diff_view::model::align_before_after;

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn logical_line_count(text: &str) -> usize {
    let newlines = text.bytes().filter(|byte| *byte == b'\n').count();
    if text.is_empty() || text.ends_with('\n') {
        newlines
    } else {
        newlines + 1
    }
}

fn assert_full_coverage(before: &str, after: &str, units: &[AlignUnit]) {
    let expected = [logical_line_count(before), logical_line_count(after)];

    for side in 0..2 {
        let mut cursor = 0;
        for unit in units {
            match unit {
                AlignUnit::Context { sides } | AlignUnit::Replace { sides } => {
                    assert_eq!(sides.len(), 2);
                    assert_eq!(
                        sides[side].start, cursor,
                        "side {side} has a gap or overlap"
                    );
                    assert!(sides[side].start <= sides[side].end);
                    cursor = sides[side].end;
                }
                AlignUnit::Add {
                    side: unit_side,
                    lines,
                }
                | AlignUnit::Remove {
                    side: unit_side,
                    lines,
                } => {
                    assert!(*unit_side < 2);
                    assert!(!lines.is_empty());
                    if *unit_side == side {
                        assert_eq!(lines.start, cursor, "side {side} has a gap or overlap");
                        cursor = lines.end;
                    }
                }
            }
        }
        assert_eq!(cursor, expected[side], "side {side} is not fully covered");
    }
}

#[test]
fn no_changes_are_one_context_unit_covering_the_file() {
    let before = "a\nb\nc\n";
    let after = "a\nb\nc\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![AlignUnit::Context {
            sides: vec![0..3, 0..3]
        }]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn pure_add_is_split_from_surrounding_context() {
    let before = "a\nc\n";
    let after = "a\nb\nc\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Add {
                side: 1,
                lines: 1..2,
            },
            AlignUnit::Context {
                sides: vec![1..2, 2..3]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn pure_remove_is_split_from_surrounding_context() {
    let before = "a\nb\nc\n";
    let after = "a\nc\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Remove {
                side: 0,
                lines: 1..2,
            },
            AlignUnit::Context {
                sides: vec![2..3, 1..2]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn replace_uses_block_level_pairing() {
    let before = "a\nold one\nold two\nz\n";
    let after = "a\nnew\nz\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Replace {
                sides: vec![1..3, 1..2]
            },
            AlignUnit::Context {
                sides: vec![3..4, 2..3]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn multiple_distributed_changes_keep_context_between_hunks() {
    let before = "a\nold one\nc\nold two\ne\n";
    let after = "a\nnew one\nc\nnew two\ne\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Replace {
                sides: vec![1..2, 1..2]
            },
            AlignUnit::Context {
                sides: vec![2..3, 2..3]
            },
            AlignUnit::Replace {
                sides: vec![3..4, 3..4]
            },
            AlignUnit::Context {
                sides: vec![4..5, 4..5]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn first_and_last_line_changes_are_covered() {
    let before = "old first\nmiddle\nold last\n";
    let after = "new first\nmiddle\nnew last\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Replace {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Context {
                sides: vec![1..2, 1..2]
            },
            AlignUnit::Replace {
                sides: vec![2..3, 2..3]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn trailing_newline_boundary_is_a_line_level_replace() {
    let before = "a\nb";
    let after = "a\nb\n";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Replace {
                sides: vec![1..2, 1..2]
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn added_final_line_without_trailing_newline_is_covered() {
    let before = "a\nb\n";
    let after = "a\nb\nc";

    let units = align_before_after(before, after, config(0));

    assert_eq!(
        units,
        vec![
            AlignUnit::Context {
                sides: vec![0..2, 0..2]
            },
            AlignUnit::Add {
                side: 1,
                lines: 2..3,
            },
        ]
    );
    assert_full_coverage(before, after, &units);
}

#[test]
fn all_side_ranges_form_complete_monotonic_sequences() {
    let cases = [
        ("", ""),
        ("a\n", "a\n"),
        ("a\nc\n", "a\nb\nc\n"),
        ("a\nb\nc\n", "a\nc\n"),
        ("a\nold one\nold two\nz\n", "a\nnew\nz\n"),
        (
            "old first\nmiddle\nold last\n",
            "new first\nmiddle\nnew last\n",
        ),
        ("a\nb", "a\nb\n"),
        ("a\nb\n", "a\nb\nc"),
    ];

    for (before, after) in cases {
        let units = align_before_after(before, after, config(1));
        assert_full_coverage(before, after, &units);
    }
}
