//! Width-independent diff-view model primitives.

use std::ops::Range;

use editor_core_diff::{DiffLineKind, LineDiffConfig, diff_line_hunks};

const BEFORE_SIDE: usize = 0;
const AFTER_SIDE: usize = 1;

/// A side document participating in a diff view.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SideDoc {
    text: String,
    logical_lines: Vec<String>,
}

impl SideDoc {
    /// Builds a side document cache from the original side text.
    pub fn from_text(text: &str) -> Self {
        Self {
            text: text.to_owned(),
            logical_lines: split_logical_lines(text),
        }
    }

    /// Returns the original text for this side.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Returns cached logical lines without trailing LF separators.
    pub fn logical_lines(&self) -> &[String] {
        &self.logical_lines
    }

    /// Returns one cached logical line by 0-based logical line index.
    pub fn logical_line(&self, logical_line: usize) -> Option<&str> {
        self.logical_lines.get(logical_line).map(String::as_str)
    }

    /// Returns the number of logical lines on this side.
    pub fn line_count(&self) -> usize {
        self.logical_lines.len()
    }
}

/// Width-independent diff model shared by projection modes.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DiffModel {
    sides: Vec<SideDoc>,
    alignment: Vec<AlignUnit>,
    line_kinds: Vec<Vec<DiffLineKind>>,
}

impl DiffModel {
    /// Builds a two-side model from before/after text and line-diff configuration.
    pub fn from_before_after(before: &str, after: &str, config: LineDiffConfig) -> Self {
        let sides = vec![SideDoc::from_text(before), SideDoc::from_text(after)];
        let alignment = align_before_after(before, after, config);
        let line_kinds = build_line_kinds(&sides, &alignment);

        Self {
            sides,
            alignment,
            line_kinds,
        }
    }

    /// Returns all side documents participating in this model.
    pub fn sides(&self) -> &[SideDoc] {
        &self.sides
    }

    /// Returns one side document by side index.
    pub fn side(&self, side: usize) -> Option<&SideDoc> {
        self.sides.get(side)
    }

    /// Returns cached width-independent alignment units.
    pub fn alignment(&self) -> &[AlignUnit] {
        &self.alignment
    }

    /// Returns the cached diff kind for a side logical line.
    pub fn side_line_kind(&self, side: usize, logical_line: usize) -> DiffLineKind {
        self.line_kinds[side][logical_line]
    }
}

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

fn split_logical_lines(text: &str) -> Vec<String> {
    if text.is_empty() {
        return Vec::new();
    }

    let text_without_final_lf = text.strip_suffix('\n').unwrap_or(text);
    text_without_final_lf
        .split('\n')
        .map(str::to_owned)
        .collect()
}

fn build_line_kinds(sides: &[SideDoc], alignment: &[AlignUnit]) -> Vec<Vec<DiffLineKind>> {
    let mut line_kinds: Vec<Vec<DiffLineKind>> = sides
        .iter()
        .map(|side| vec![DiffLineKind::Context; side.line_count()])
        .collect();

    for unit in alignment {
        match unit {
            AlignUnit::Context { sides } => {
                for (side, lines) in sides.iter().enumerate() {
                    mark_lines(&mut line_kinds, side, lines, DiffLineKind::Context);
                }
            }
            AlignUnit::Replace { sides } => {
                for (side, lines) in sides.iter().enumerate() {
                    let kind = if side == BEFORE_SIDE {
                        DiffLineKind::Remove
                    } else {
                        DiffLineKind::Add
                    };
                    mark_lines(&mut line_kinds, side, lines, kind);
                }
            }
            AlignUnit::Add { side, lines } => {
                mark_lines(&mut line_kinds, *side, lines, DiffLineKind::Add);
            }
            AlignUnit::Remove { side, lines } => {
                mark_lines(&mut line_kinds, *side, lines, DiffLineKind::Remove);
            }
        }
    }

    line_kinds
}

fn mark_lines(
    line_kinds: &mut [Vec<DiffLineKind>],
    side: usize,
    lines: &Range<usize>,
    kind: DiffLineKind,
) {
    debug_assert!(side < line_kinds.len());
    if let Some(side_kinds) = line_kinds.get_mut(side) {
        debug_assert!(lines.end <= side_kinds.len());
        for logical_line in lines.clone() {
            side_kinds[logical_line] = kind;
        }
    }
}
