//! Diff / hunk primitives for editor-core integrations.
//!
//! This crate focuses on a pragmatic line-based diff model:
//! - input: `before` and `after` as `&str`
//! - output: hunks with (before/after) line ranges and per-line change records

use std::ops::Range;

/// Which diff algorithm to use.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffAlgorithm {
    /// Git-like, generally human-friendly diffs (recommended default).
    Histogram,
    /// Myers (fast, classic).
    Myers,
    /// Myers minimal edit script (may be less readable).
    MyersMinimal,
}

impl Default for DiffAlgorithm {
    fn default() -> Self {
        Self::Histogram
    }
}

impl From<DiffAlgorithm> for imara_diff::Algorithm {
    fn from(value: DiffAlgorithm) -> Self {
        match value {
            DiffAlgorithm::Histogram => imara_diff::Algorithm::Histogram,
            DiffAlgorithm::Myers => imara_diff::Algorithm::Myers,
            DiffAlgorithm::MyersMinimal => imara_diff::Algorithm::MyersMinimal,
        }
    }
}

/// Configuration for line diff computation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineDiffConfig {
    /// Diff algorithm.
    pub algorithm: DiffAlgorithm,
    /// Number of unchanged (context) lines to include around each change group.
    pub context_lines: usize,
    /// Whether to apply postprocessing heuristics for line diffs.
    pub postprocess_lines: bool,
}

impl Default for LineDiffConfig {
    fn default() -> Self {
        Self {
            algorithm: DiffAlgorithm::Histogram,
            context_lines: 3,
            postprocess_lines: true,
        }
    }
}

/// The kind of a single diff line within a hunk.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DiffLineKind {
    Context,
    Add,
    Remove,
}

impl DiffLineKind {
    pub fn is_change(self) -> bool {
        !matches!(self, DiffLineKind::Context)
    }
}

/// A single line record in a line-based diff.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct DiffLine<'a> {
    pub kind: DiffLineKind,
    /// 0-based line index in the `before` text.
    pub before_line: Option<usize>,
    /// 0-based line index in the `after` text.
    pub after_line: Option<usize>,
    /// The full line slice (including its newline if present).
    pub text: &'a str,
}

/// A diff hunk, line-indexed on both sides.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineHunk<'a> {
    /// 0-based line range in `before` covered by this hunk (includes context lines).
    pub before: Range<usize>,
    /// 0-based line range in `after` covered by this hunk (includes context lines).
    pub after: Range<usize>,
    /// Per-line records in display order (unified diff order).
    pub lines: Vec<DiffLine<'a>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct HunkRanges {
    before: Range<usize>,
    after: Range<usize>,
}

fn merge_overlapping_ranges(mut ranges: Vec<HunkRanges>) -> Vec<HunkRanges> {
    if ranges.is_empty() {
        return ranges;
    }

    ranges.sort_by_key(|r| r.before.start);

    let mut merged: Vec<HunkRanges> = Vec::with_capacity(ranges.len());
    for r in ranges {
        match merged.last_mut() {
            None => merged.push(r),
            Some(last) => {
                let overlaps_before = r.before.start <= last.before.end;
                let overlaps_after = r.after.start <= last.after.end;
                if overlaps_before || overlaps_after {
                    last.before.end = last.before.end.max(r.before.end);
                    last.after.end = last.after.end.max(r.after.end);
                } else {
                    merged.push(r);
                }
            }
        }
    }
    merged
}

fn expand_hunk_with_context(
    hunk: imara_diff::Hunk,
    before_len: usize,
    after_len: usize,
    context_lines: usize,
) -> HunkRanges {
    let before_start = (hunk.before.start as usize).saturating_sub(context_lines);
    let after_start = (hunk.after.start as usize).saturating_sub(context_lines);

    let before_end = (hunk.before.end as usize).saturating_add(context_lines).min(before_len);
    let after_end = (hunk.after.end as usize).saturating_add(context_lines).min(after_len);

    HunkRanges {
        before: before_start..before_end,
        after: after_start..after_end,
    }
}

fn op_in_hunk(op: DiffLine<'_>, before: &Range<usize>, after: &Range<usize>) -> bool {
    let in_before = op.before_line.is_some_and(|idx| before.contains(&idx));
    let in_after = op.after_line.is_some_and(|idx| after.contains(&idx));

    match op.kind {
        DiffLineKind::Context => in_before && in_after,
        DiffLineKind::Add => in_after,
        DiffLineKind::Remove => in_before,
    }
}

/// Compute line hunks between `before` and `after` (with context), suitable for:
/// - modified-line gutter indicators
/// - diff/merge views (UI aside)
///
/// The returned hunks:
/// - are monotonically increasing in both `before` and `after`
/// - include up to `config.context_lines` unchanged lines around each change group
/// - contain per-line records in unified diff order (`-` before `+` for modifications)
pub fn diff_line_hunks<'a>(before: &'a str, after: &'a str, config: LineDiffConfig) -> Vec<LineHunk<'a>> {
    let before_lines: Vec<&'a str> = imara_diff::sources::lines(before).collect();
    let after_lines: Vec<&'a str> = imara_diff::sources::lines(after).collect();

    let input = imara_diff::InternedInput::new(before, after);
    let mut diff = imara_diff::Diff::compute(config.algorithm.into(), &input);
    if config.postprocess_lines {
        diff.postprocess_lines(&input);
    }

    let raw_hunks: Vec<imara_diff::Hunk> = diff.hunks().collect();
    if raw_hunks.is_empty() {
        return Vec::new();
    }

    let expanded: Vec<HunkRanges> = raw_hunks
        .into_iter()
        .map(|h| expand_hunk_with_context(h, before_lines.len(), after_lines.len(), config.context_lines))
        .collect();
    let hunks = merge_overlapping_ranges(expanded);

    // Build a full unified-style line op list once, then slice into hunks by line indices.
    let mut ops: Vec<DiffLine<'a>> = Vec::with_capacity(before_lines.len() + diff.count_additions() as usize);
    let mut i_before: u32 = 0;
    let mut i_after: u32 = 0;
    while (i_before as usize) < before_lines.len() || (i_after as usize) < after_lines.len() {
        if (i_before as usize) < before_lines.len() && diff.is_removed(i_before) {
            ops.push(DiffLine {
                kind: DiffLineKind::Remove,
                before_line: Some(i_before as usize),
                after_line: None,
                text: before_lines[i_before as usize],
            });
            i_before += 1;
            continue;
        }
        if (i_after as usize) < after_lines.len() && diff.is_added(i_after) {
            ops.push(DiffLine {
                kind: DiffLineKind::Add,
                before_line: None,
                after_line: Some(i_after as usize),
                text: after_lines[i_after as usize],
            });
            i_after += 1;
            continue;
        }

        if (i_before as usize) < before_lines.len() && (i_after as usize) < after_lines.len() {
            ops.push(DiffLine {
                kind: DiffLineKind::Context,
                before_line: Some(i_before as usize),
                after_line: Some(i_after as usize),
                text: after_lines[i_after as usize],
            });
            i_before += 1;
            i_after += 1;
            continue;
        }

        // Fallback for unexpected alignment issues; should be unreachable for a valid diff.
        if (i_before as usize) < before_lines.len() {
            ops.push(DiffLine {
                kind: DiffLineKind::Remove,
                before_line: Some(i_before as usize),
                after_line: None,
                text: before_lines[i_before as usize],
            });
            i_before += 1;
        } else if (i_after as usize) < after_lines.len() {
            ops.push(DiffLine {
                kind: DiffLineKind::Add,
                before_line: None,
                after_line: Some(i_after as usize),
                text: after_lines[i_after as usize],
            });
            i_after += 1;
        }
    }

    hunks
        .into_iter()
        .map(|hr| {
            let lines: Vec<DiffLine<'a>> = ops
                .iter()
                .copied()
                .filter(|op| op_in_hunk(*op, &hr.before, &hr.after))
                .collect();

            LineHunk {
                before: hr.before,
                after: hr.after,
                lines,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_changes_returns_no_hunks() {
        let before = "a\nb\n";
        let after = "a\nb\n";
        let hunks = diff_line_hunks(before, after, LineDiffConfig::default());
        assert!(hunks.is_empty());
    }
}
