//! Width-independent diff-view model primitives.

use std::ops::Range;

use editor_core_diff::{DiffLineKind, LineDiffConfig, diff_line_hunks};

/// A side document participating in a diff view.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SideDoc;

/// Width-independent diff model placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DiffModel;

/// Logical-line alignment unit shared by model and projection layers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AlignUnit {
    /// Unchanged logical lines present on every side.
    Context { sides: Vec<Range<usize>> },
    /// A changed block paired at block granularity, not per-line granularity.
    Replace { sides: Vec<Range<usize>> },
    /// Logical lines that only exist on one side.
    Add { side: usize, lines: Range<usize> },
    /// Logical lines that only exist on one side.
    Remove { side: usize, lines: Range<usize> },
}

/// Builds width-independent alignment units from a before/after text pair.
pub fn align_before_after(before: &str, after: &str, config: LineDiffConfig) -> Vec<AlignUnit> {
    const BEFORE_SIDE: usize = 0;
    const AFTER_SIDE: usize = 1;

    let before_len = logical_line_count(before);
    let after_len = logical_line_count(after);
    let hunks = diff_line_hunks(before, after, config);

    let mut units = Vec::new();
    let mut before_cursor = 0;
    let mut after_cursor = 0;

    for hunk in hunks {
        push_context(
            &mut units,
            before_cursor..hunk.before.start,
            after_cursor..hunk.after.start,
        );
        before_cursor = hunk.before.start;
        after_cursor = hunk.after.start;

        let mut line_index = 0;
        while line_index < hunk.lines.len() {
            match hunk.lines[line_index].kind {
                DiffLineKind::Context => {
                    let before_start = before_cursor;
                    let after_start = after_cursor;
                    while line_index < hunk.lines.len()
                        && hunk.lines[line_index].kind == DiffLineKind::Context
                    {
                        advance_cursor(&mut before_cursor, hunk.lines[line_index].before_line);
                        advance_cursor(&mut after_cursor, hunk.lines[line_index].after_line);
                        line_index += 1;
                    }
                    push_context(
                        &mut units,
                        before_start..before_cursor,
                        after_start..after_cursor,
                    );
                }
                DiffLineKind::Add | DiffLineKind::Remove => {
                    let before_start = before_cursor;
                    let after_start = after_cursor;
                    let mut saw_add = false;
                    let mut saw_remove = false;

                    while line_index < hunk.lines.len()
                        && hunk.lines[line_index].kind != DiffLineKind::Context
                    {
                        match hunk.lines[line_index].kind {
                            DiffLineKind::Context => unreachable!(),
                            DiffLineKind::Add => {
                                saw_add = true;
                                advance_cursor(
                                    &mut after_cursor,
                                    hunk.lines[line_index].after_line,
                                );
                            }
                            DiffLineKind::Remove => {
                                saw_remove = true;
                                advance_cursor(
                                    &mut before_cursor,
                                    hunk.lines[line_index].before_line,
                                );
                            }
                        }
                        line_index += 1;
                    }

                    let before_range = before_start..before_cursor;
                    let after_range = after_start..after_cursor;
                    match (saw_remove, saw_add) {
                        (true, true) => push_unit(
                            &mut units,
                            AlignUnit::Replace {
                                sides: vec![before_range, after_range],
                            },
                        ),
                        (true, false) => push_unit(
                            &mut units,
                            AlignUnit::Remove {
                                side: BEFORE_SIDE,
                                lines: before_range,
                            },
                        ),
                        (false, true) => push_unit(
                            &mut units,
                            AlignUnit::Add {
                                side: AFTER_SIDE,
                                lines: after_range,
                            },
                        ),
                        (false, false) => unreachable!(),
                    }
                }
            }
        }

        debug_assert_eq!(before_cursor, hunk.before.end);
        debug_assert_eq!(after_cursor, hunk.after.end);
    }

    push_context(
        &mut units,
        before_cursor..before_len,
        after_cursor..after_len,
    );
    units
}

fn logical_line_count(text: &str) -> usize {
    let newlines = text.bytes().filter(|byte| *byte == b'\n').count();
    if text.is_empty() || text.ends_with('\n') {
        newlines
    } else {
        newlines + 1
    }
}

fn advance_cursor(cursor: &mut usize, line: Option<usize>) {
    if let Some(line) = line {
        debug_assert_eq!(*cursor, line);
        *cursor = line + 1;
    }
}

fn push_context(units: &mut Vec<AlignUnit>, before: Range<usize>, after: Range<usize>) {
    if before.is_empty() && after.is_empty() {
        return;
    }

    push_unit(
        units,
        AlignUnit::Context {
            sides: vec![before, after],
        },
    );
}

fn push_unit(units: &mut Vec<AlignUnit>, unit: AlignUnit) {
    if let AlignUnit::Context { sides } = &unit
        && let Some(AlignUnit::Context { sides: previous }) = units.last_mut()
    {
        let can_merge = previous.len() == sides.len()
            && previous
                .iter()
                .zip(sides.iter())
                .all(|(previous, next)| previous.end == next.start);

        if can_merge {
            for (previous, next) in previous.iter_mut().zip(sides.iter()) {
                previous.end = next.end;
            }
            return;
        }
    }

    units.push(unit);
}
