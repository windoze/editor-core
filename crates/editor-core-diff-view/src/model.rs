//! Width-independent diff-view model primitives.

use std::fmt;
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
    ///
    /// The text is normalized to LF line endings (CRLF and lone CR both become LF) before it is
    /// stored and split into logical lines. This keeps the model's line count and per-line content
    /// consistent with the projection layer, which runs the text through `SnapshotGenerator` (that
    /// applies the same normalization). Without this, a lone CR would make the model see fewer
    /// lines than the projection, causing content to be dropped and line numbers to misalign; and
    /// CRLF would leave a stray `\r` in `logical_lines` that the projected cells do not contain.
    pub fn from_text(text: &str) -> Self {
        let normalized = normalize_line_endings_to_lf(text);
        let logical_lines = split_logical_lines(&normalized);
        Self {
            text: normalized,
            logical_lines,
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

    /// Builds a two-side model from a before-side file and a single-file unified diff patch.
    ///
    /// The patch is interpreted as a unified diff from `file` to the after side. Hunk records
    /// drive both after-text reconstruction and alignment construction, so this path does not
    /// re-run the line diff algorithm over the reconstructed full texts.
    pub fn from_file_and_patch(file: &str, patch: &str) -> Result<Self, PatchParseError> {
        let (after, alignment) = apply_unified_patch(file, patch)?;
        let sides = vec![SideDoc::from_text(file), SideDoc::from_text(&after)];
        let line_kinds = build_line_kinds(&sides, &alignment);

        Ok(Self {
            sides,
            alignment,
            line_kinds,
        })
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

/// Error returned when a unified diff patch cannot be parsed or applied to the input file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PatchParseError {
    line: Option<usize>,
    message: String,
}

impl PatchParseError {
    /// Returns the 1-based patch line associated with the error, when available.
    pub fn line(&self) -> Option<usize> {
        self.line
    }

    /// Returns a human-readable parse or apply error message.
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for PatchParseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.line {
            Some(line) => write!(formatter, "patch line {line}: {}", self.message),
            None => formatter.write_str(&self.message),
        }
    }
}

impl std::error::Error for PatchParseError {}

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

#[derive(Debug, Clone, PartialEq, Eq)]
struct PatchHunkHeader {
    before: Range<usize>,
    after: Range<usize>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PatchRecordKind {
    Context,
    Add,
    Remove,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PatchRecord {
    kind: PatchRecordKind,
    text: String,
    line: usize,
}

fn apply_unified_patch(
    file: &str,
    patch: &str,
) -> Result<(String, Vec<AlignUnit>), PatchParseError> {
    let source_lines = split_text_lines(file);
    let patch_lines = split_patch_lines(patch);
    let mut after = String::with_capacity(file.len());
    let mut units = Vec::new();
    let mut before_cursor = 0;
    let mut after_cursor = 0;
    let mut patch_index = 0;
    let mut seen_hunk = false;

    while patch_index < patch_lines.len() {
        let line = patch_lines[patch_index];
        let line_number = patch_index + 1;

        if is_hunk_header(line) {
            seen_hunk = true;
            let header = parse_hunk_header(line, line_number)?;
            append_unchanged_before_hunk(
                &source_lines,
                &mut after,
                &mut units,
                &mut before_cursor,
                &mut after_cursor,
                &header,
                line_number,
            )?;

            patch_index += 1;
            let (records, next_index) = parse_hunk_records(&patch_lines, patch_index, &header)?;
            apply_hunk_records(
                &source_lines,
                &mut after,
                &mut units,
                &mut before_cursor,
                &mut after_cursor,
                &header,
                &records,
            )?;
            patch_index = next_index;
        } else {
            if is_no_newline_marker(line) {
                return Err(patch_error(
                    Some(line_number),
                    "no-newline marker appeared outside a hunk",
                ));
            }
            if seen_hunk {
                return Err(patch_error(
                    Some(line_number),
                    "unexpected trailing content after unified diff hunk",
                ));
            }
            if !is_ignorable_preamble_line(line) {
                return Err(patch_error(
                    Some(line_number),
                    "unexpected content before first unified diff hunk",
                ));
            }
            patch_index += 1;
        }
    }

    append_unchanged_tail(
        &source_lines,
        &mut after,
        &mut units,
        before_cursor,
        after_cursor,
    );

    Ok((after, units))
}

fn split_text_lines(text: &str) -> Vec<&str> {
    if text.is_empty() {
        Vec::new()
    } else {
        text.split_inclusive('\n').collect()
    }
}

fn split_patch_lines(patch: &str) -> Vec<&str> {
    if patch.is_empty() {
        Vec::new()
    } else {
        patch.split_inclusive('\n').collect()
    }
}

fn is_hunk_header(line: &str) -> bool {
    line.trim_end_matches(['\r', '\n']).starts_with("@@ ")
}

fn is_no_newline_marker(line: &str) -> bool {
    line.trim_end_matches(['\r', '\n']) == r"\ No newline at end of file"
}

fn is_ignorable_preamble_line(line: &str) -> bool {
    let line = line.trim_end_matches(['\r', '\n']);
    line.is_empty()
        || line.starts_with("diff --git ")
        || line.starts_with("index ")
        || line.starts_with("old mode ")
        || line.starts_with("new mode ")
        || line.starts_with("deleted file mode ")
        || line.starts_with("new file mode ")
        || line.starts_with("similarity index ")
        || line.starts_with("dissimilarity index ")
        || line.starts_with("rename from ")
        || line.starts_with("rename to ")
        || line.starts_with("copy from ")
        || line.starts_with("copy to ")
        || line.starts_with("--- ")
        || line.starts_with("+++ ")
}

fn parse_hunk_header(line: &str, line_number: usize) -> Result<PatchHunkHeader, PatchParseError> {
    let trimmed = line.trim_end_matches(['\r', '\n']);
    let mut parts = trimmed.split_whitespace();
    if parts.next() != Some("@@") {
        return Err(patch_error(
            Some(line_number),
            "expected unified diff hunk header",
        ));
    }

    let before = parts
        .next()
        .ok_or_else(|| patch_error(Some(line_number), "missing before range in hunk header"))?;
    let after = parts
        .next()
        .ok_or_else(|| patch_error(Some(line_number), "missing after range in hunk header"))?;

    if parts.next() != Some("@@") {
        return Err(patch_error(
            Some(line_number),
            "missing closing @@ in hunk header",
        ));
    }

    Ok(PatchHunkHeader {
        before: parse_unified_range(before, '-', line_number)?,
        after: parse_unified_range(after, '+', line_number)?,
    })
}

fn parse_unified_range(
    token: &str,
    prefix: char,
    line_number: usize,
) -> Result<Range<usize>, PatchParseError> {
    let body = token.strip_prefix(prefix).ok_or_else(|| {
        patch_error(
            Some(line_number),
            format!("expected {prefix} range in hunk header"),
        )
    })?;
    let (start, count) = match body.split_once(',') {
        Some((start, count)) => (start, count),
        None => (body, "1"),
    };

    let start = parse_hunk_number(start, line_number, "range start")?;
    let count = parse_hunk_number(count, line_number, "range count")?;
    let start_index = if count == 0 {
        start
    } else {
        start.checked_sub(1).ok_or_else(|| {
            patch_error(
                Some(line_number),
                "non-empty hunk range must start at line 1 or greater",
            )
        })?
    };
    let end = start_index
        .checked_add(count)
        .ok_or_else(|| patch_error(Some(line_number), "hunk range overflows platform usize"))?;

    Ok(start_index..end)
}

fn parse_hunk_number(
    value: &str,
    line_number: usize,
    label: &str,
) -> Result<usize, PatchParseError> {
    if value.is_empty() {
        return Err(patch_error(
            Some(line_number),
            format!("empty {label} in hunk header"),
        ));
    }

    value
        .parse::<usize>()
        .map_err(|_| patch_error(Some(line_number), format!("invalid {label} in hunk header")))
}

fn append_unchanged_before_hunk(
    source_lines: &[&str],
    after: &mut String,
    units: &mut Vec<AlignUnit>,
    before_cursor: &mut usize,
    after_cursor: &mut usize,
    header: &PatchHunkHeader,
    line_number: usize,
) -> Result<(), PatchParseError> {
    if header.before.start < *before_cursor {
        return Err(patch_error(
            Some(line_number),
            "hunk before range overlaps a previous hunk",
        ));
    }
    if header.before.start > source_lines.len() {
        return Err(patch_error(
            Some(line_number),
            "hunk before range starts beyond input file",
        ));
    }

    let unchanged_len = header.before.start - *before_cursor;
    let expected_after_start = after_cursor.checked_add(unchanged_len).ok_or_else(|| {
        patch_error(
            Some(line_number),
            "after line cursor overflows platform usize",
        )
    })?;
    if header.after.start != expected_after_start {
        return Err(patch_error(
            Some(line_number),
            "hunk after range is inconsistent with preceding unchanged lines",
        ));
    }

    after.push_str(&source_lines[*before_cursor..header.before.start].concat());
    push_context(
        units,
        *before_cursor..header.before.start,
        *after_cursor..header.after.start,
    );
    *before_cursor = header.before.start;
    *after_cursor = header.after.start;
    Ok(())
}

fn parse_hunk_records(
    patch_lines: &[&str],
    mut patch_index: usize,
    header: &PatchHunkHeader,
) -> Result<(Vec<PatchRecord>, usize), PatchParseError> {
    let mut records = Vec::new();
    let mut before_count = 0;
    let mut after_count = 0;
    let expected_before = header.before.end - header.before.start;
    let expected_after = header.after.end - header.after.start;

    while before_count < expected_before || after_count < expected_after {
        if patch_index >= patch_lines.len() {
            return Err(patch_error(
                None,
                "patch ended before hunk line counts were satisfied",
            ));
        }

        let line = patch_lines[patch_index];
        let line_number = patch_index + 1;
        if is_no_newline_marker(line) {
            strip_previous_record_newline(&mut records, line_number)?;
            patch_index += 1;
            continue;
        }
        if is_hunk_header(line) {
            return Err(patch_error(
                Some(line_number),
                "next hunk header appeared before current hunk counts were satisfied",
            ));
        }

        let (kind, text) = parse_hunk_record_line(line, line_number)?;
        match kind {
            PatchRecordKind::Context => {
                before_count += 1;
                after_count += 1;
            }
            PatchRecordKind::Add => {
                after_count += 1;
            }
            PatchRecordKind::Remove => {
                before_count += 1;
            }
        }
        if before_count > expected_before || after_count > expected_after {
            return Err(patch_error(
                Some(line_number),
                "hunk line count exceeds header range",
            ));
        }

        records.push(PatchRecord {
            kind,
            text: text.to_owned(),
            line: line_number,
        });
        patch_index += 1;
    }

    if patch_index < patch_lines.len() && is_no_newline_marker(patch_lines[patch_index]) {
        strip_previous_record_newline(&mut records, patch_index + 1)?;
        patch_index += 1;
    }

    Ok((records, patch_index))
}

fn parse_hunk_record_line(
    line: &str,
    line_number: usize,
) -> Result<(PatchRecordKind, &str), PatchParseError> {
    let Some(prefix) = line.as_bytes().first().copied() else {
        return Err(patch_error(Some(line_number), "empty line inside hunk"));
    };
    let text = &line[1..];

    match prefix {
        b' ' => Ok((PatchRecordKind::Context, text)),
        b'+' => Ok((PatchRecordKind::Add, text)),
        b'-' => Ok((PatchRecordKind::Remove, text)),
        _ => Err(patch_error(
            Some(line_number),
            "hunk line must start with space, +, -, or no-newline marker",
        )),
    }
}

fn strip_previous_record_newline(
    records: &mut [PatchRecord],
    line_number: usize,
) -> Result<(), PatchParseError> {
    let previous = records.last_mut().ok_or_else(|| {
        patch_error(
            Some(line_number),
            "no-newline marker has no preceding hunk line",
        )
    })?;
    if previous.text.ends_with("\r\n") {
        previous.text.truncate(previous.text.len() - 2);
    } else if previous.text.ends_with('\n') {
        previous.text.pop();
    }
    Ok(())
}

fn apply_hunk_records(
    source_lines: &[&str],
    after: &mut String,
    units: &mut Vec<AlignUnit>,
    before_cursor: &mut usize,
    after_cursor: &mut usize,
    header: &PatchHunkHeader,
    records: &[PatchRecord],
) -> Result<(), PatchParseError> {
    let mut record_index = 0;
    while record_index < records.len() {
        match records[record_index].kind {
            PatchRecordKind::Context => {
                let before_start = *before_cursor;
                let after_start = *after_cursor;
                while record_index < records.len()
                    && records[record_index].kind == PatchRecordKind::Context
                {
                    apply_source_record(
                        source_lines,
                        after,
                        before_cursor,
                        after_cursor,
                        &records[record_index],
                    )?;
                    record_index += 1;
                }
                push_context(
                    units,
                    before_start..*before_cursor,
                    after_start..*after_cursor,
                );
            }
            PatchRecordKind::Add | PatchRecordKind::Remove => {
                let before_start = *before_cursor;
                let after_start = *after_cursor;
                let mut saw_add = false;
                let mut saw_remove = false;

                while record_index < records.len()
                    && records[record_index].kind != PatchRecordKind::Context
                {
                    match records[record_index].kind {
                        PatchRecordKind::Context => unreachable!(),
                        PatchRecordKind::Add => {
                            saw_add = true;
                            after.push_str(&records[record_index].text);
                            *after_cursor += 1;
                        }
                        PatchRecordKind::Remove => {
                            saw_remove = true;
                            validate_source_record(
                                source_lines,
                                *before_cursor,
                                &records[record_index],
                            )?;
                            *before_cursor += 1;
                        }
                    }
                    record_index += 1;
                }

                push_change_unit(
                    units,
                    saw_remove,
                    saw_add,
                    before_start..*before_cursor,
                    after_start..*after_cursor,
                );
            }
        }
    }

    if *before_cursor != header.before.end {
        return Err(patch_error(
            None,
            "applied hunk before line count does not match header",
        ));
    }
    if *after_cursor != header.after.end {
        return Err(patch_error(
            None,
            "applied hunk after line count does not match header",
        ));
    }

    Ok(())
}

fn apply_source_record(
    source_lines: &[&str],
    after: &mut String,
    before_cursor: &mut usize,
    after_cursor: &mut usize,
    record: &PatchRecord,
) -> Result<(), PatchParseError> {
    validate_source_record(source_lines, *before_cursor, record)?;
    after.push_str(&record.text);
    *before_cursor += 1;
    *after_cursor += 1;
    Ok(())
}

fn validate_source_record(
    source_lines: &[&str],
    before_cursor: usize,
    record: &PatchRecord,
) -> Result<(), PatchParseError> {
    let Some(source_line) = source_lines.get(before_cursor) else {
        return Err(patch_error(
            Some(record.line),
            "hunk reads beyond input file",
        ));
    };
    if *source_line != record.text {
        return Err(patch_error(
            Some(record.line),
            "hunk line does not match input file",
        ));
    }
    Ok(())
}

fn push_change_unit(
    units: &mut Vec<AlignUnit>,
    saw_remove: bool,
    saw_add: bool,
    before: Range<usize>,
    after: Range<usize>,
) {
    match (saw_remove, saw_add) {
        (true, true) => push_unit(
            units,
            AlignUnit::Replace {
                sides: vec![before, after],
            },
        ),
        (true, false) => push_unit(
            units,
            AlignUnit::Remove {
                side: BEFORE_SIDE,
                lines: before,
            },
        ),
        (false, true) => push_unit(
            units,
            AlignUnit::Add {
                side: AFTER_SIDE,
                lines: after,
            },
        ),
        (false, false) => unreachable!(),
    }
}

fn append_unchanged_tail(
    source_lines: &[&str],
    after: &mut String,
    units: &mut Vec<AlignUnit>,
    before_cursor: usize,
    after_cursor: usize,
) {
    after.push_str(&source_lines[before_cursor..].concat());
    push_context(
        units,
        before_cursor..source_lines.len(),
        after_cursor..after_cursor + source_lines.len() - before_cursor,
    );
}

fn patch_error(line: Option<usize>, message: impl Into<String>) -> PatchParseError {
    PatchParseError {
        line,
        message: message.into(),
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

/// Normalize line endings to LF, matching `editor_core`'s internal text model / `SnapshotGenerator`:
/// CRLF (`\r\n`) and lone CR (`\r`) both become LF (`\n`).
fn normalize_line_endings_to_lf(text: &str) -> String {
    if text.contains('\r') {
        text.replace("\r\n", "\n").replace('\r', "\n")
    } else {
        text.to_owned()
    }
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
