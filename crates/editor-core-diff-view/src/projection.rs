//! Width-dependent diff projection primitives.

use std::ops::Range;

use editor_core::{Cell, snapshot::SnapshotGenerator};
use editor_core_diff::DiffLineKind;

use crate::model::{AlignUnit, DiffModel, SideDoc};
use crate::style;

const BEFORE_SIDE: usize = 0;
const AFTER_SIDE: usize = 1;

/// Diff projection mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffMode {
    /// Single-column unified diff, with removed rows before added rows.
    Unified,
    /// Two-column side-by-side diff with spacer rows for per-unit alignment.
    SideBySide,
}

/// Width-dependent projection over a [`DiffModel`].
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DiffProjection {
    /// Number of projected columns.
    pub columns: usize,
    /// Unified visual row axis shared by all columns.
    pub rows: Vec<Row>,
}

impl DiffProjection {
    /// Rebuilds the full projection for the requested mode and column widths.
    pub fn build(model: &DiffModel, mode: DiffMode, per_column_widths: &[usize]) -> Self {
        match mode {
            DiffMode::Unified => project_unified(model, per_column_widths),
            DiffMode::SideBySide => project_side_by_side(model, per_column_widths),
        }
    }

    /// Returns the number of projected columns.
    pub fn columns(&self) -> usize {
        self.columns
    }

    /// Returns the unified visual row axis.
    pub fn rows(&self) -> &[Row] {
        &self.rows
    }
}

/// One row in the unified visual row axis.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Row {
    /// Per-column slots. `slots.len()` equals [`DiffProjection::columns`].
    pub slots: Vec<RowSlot>,
}

impl Row {
    /// Builds a row from already projected column slots.
    pub fn new(slots: Vec<RowSlot>) -> Self {
        Self { slots }
    }

    /// Returns the per-column slots for this row.
    pub fn slots(&self) -> &[RowSlot] {
        &self.slots
    }
}

/// Pure gutter data for a projected row slot.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Gutter {
    /// 0-based line index in the before side, when this slot should show one.
    pub before_line: Option<usize>,
    /// 0-based line index in the after side, when this slot should show one.
    pub after_line: Option<usize>,
    /// Diff line marker displayed by the host gutter, currently `+` or `-`.
    pub marker: Option<char>,
}

impl Gutter {
    /// Returns an empty gutter for spacers and wrapped continuation segments.
    pub fn empty() -> Self {
        Self::default()
    }
}

/// One projected row slot.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RowSlot {
    /// A real wrapped visual segment from one side document.
    Line {
        /// Side index in the source [`DiffModel`].
        side: usize,
        /// 0-based logical line index within `side`.
        logical_line: usize,
        /// 0-based wrapped visual segment within the logical line.
        visual_in_logical: usize,
        /// Diff change kind for the logical line.
        change: DiffLineKind,
        /// Pure gutter metadata for line numbers and diff markers.
        gutter: Gutter,
        /// Cells for this wrapped visual segment with diff-semantic styles applied.
        cells: Vec<Cell>,
    },
    /// A filler row used by aligned multi-column projections.
    Spacer {
        /// Diff change kind for the alignment unit that owns this spacer.
        change: DiffLineKind,
        /// Empty gutter metadata; spacers do not correspond to source lines.
        gutter: Gutter,
        /// Styled placeholder cells for the spacer row.
        cells: Vec<Cell>,
    },
}

impl RowSlot {
    /// Returns the cells projected for this slot.
    pub fn cells(&self) -> &[Cell] {
        match self {
            RowSlot::Line { cells, .. } | RowSlot::Spacer { cells, .. } => cells,
        }
    }

    /// Returns the pure gutter metadata attached to this slot.
    pub fn gutter(&self) -> Gutter {
        match self {
            RowSlot::Line { gutter, .. } | RowSlot::Spacer { gutter, .. } => *gutter,
        }
    }
}

/// Builds the single-column unified projection.
pub fn project_unified(model: &DiffModel, per_column_widths: &[usize]) -> DiffProjection {
    let width = unified_width(per_column_widths);
    let wrapped_sides = wrap_all_sides(model, width);
    let mut rows = Vec::new();

    for unit in model.alignment() {
        match unit {
            AlignUnit::Context { sides } => {
                assert!(
                    sides.len() >= 2,
                    "context alignment units require before and after sides"
                );
                let side = context_display_side(sides);
                push_line_rows(
                    &mut rows,
                    &wrapped_sides,
                    side,
                    &sides[side],
                    DiffLineKind::Context,
                    GutterMapping::UnifiedContext {
                        before_start: sides[BEFORE_SIDE].start,
                        after_start: sides[AFTER_SIDE].start,
                        display_start: sides[side].start,
                    },
                );
            }
            AlignUnit::Replace { sides } => {
                assert!(
                    sides.len() >= 2,
                    "replace alignment units require before and after sides"
                );
                push_line_rows(
                    &mut rows,
                    &wrapped_sides,
                    BEFORE_SIDE,
                    &sides[BEFORE_SIDE],
                    DiffLineKind::Remove,
                    GutterMapping::SideLine,
                );
                push_line_rows(
                    &mut rows,
                    &wrapped_sides,
                    AFTER_SIDE,
                    &sides[AFTER_SIDE],
                    DiffLineKind::Add,
                    GutterMapping::SideLine,
                );
            }
            AlignUnit::Add { side, lines } => {
                push_line_rows(
                    &mut rows,
                    &wrapped_sides,
                    *side,
                    lines,
                    DiffLineKind::Add,
                    GutterMapping::SideLine,
                );
            }
            AlignUnit::Remove { side, lines } => {
                push_line_rows(
                    &mut rows,
                    &wrapped_sides,
                    *side,
                    lines,
                    DiffLineKind::Remove,
                    GutterMapping::SideLine,
                );
            }
        }
    }

    DiffProjection { columns: 1, rows }
}

fn project_side_by_side(model: &DiffModel, per_column_widths: &[usize]) -> DiffProjection {
    let widths = side_by_side_widths(per_column_widths);
    let wrapped_sides = wrap_sides_by_widths(model, &widths);
    let mut rows = Vec::new();

    for unit in model.alignment() {
        let mut columns = [Vec::new(), Vec::new()];
        let spacer_changes = push_side_by_side_unit(&mut columns, &wrapped_sides, unit);
        push_aligned_unit_rows(&mut rows, columns, spacer_changes);
    }

    DiffProjection { columns: 2, rows }
}

fn unified_width(per_column_widths: &[usize]) -> usize {
    assert_eq!(
        per_column_widths.len(),
        1,
        "unified projection requires exactly one column width"
    );
    let width = per_column_widths[0];
    assert!(width > 0, "column width must be greater than zero");
    width
}

fn side_by_side_widths(per_column_widths: &[usize]) -> [usize; 2] {
    assert_eq!(
        per_column_widths.len(),
        2,
        "side-by-side projection requires exactly two column widths"
    );
    let widths = [per_column_widths[0], per_column_widths[1]];
    assert!(
        widths.iter().all(|width| *width > 0),
        "column widths must be greater than zero"
    );
    widths
}

fn context_display_side(sides: &[Range<usize>]) -> usize {
    assert!(!sides.is_empty(), "context alignment unit has no sides");
    sides.len() - 1
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WrappedSide {
    visual_segments_by_line: Vec<Vec<WrappedSegment>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WrappedSegment {
    visual_in_logical: usize,
    cells: Vec<Cell>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GutterMapping {
    SideLine,
    UnifiedContext {
        before_start: usize,
        after_start: usize,
        display_start: usize,
    },
}

impl GutterMapping {
    fn gutter(
        self,
        side: usize,
        logical_line: usize,
        visual_in_logical: usize,
        change: DiffLineKind,
    ) -> Gutter {
        if visual_in_logical != 0 {
            return Gutter::empty();
        }

        match self {
            GutterMapping::SideLine => side_line_gutter(side, logical_line, change),
            GutterMapping::UnifiedContext {
                before_start,
                after_start,
                display_start,
            } => {
                let offset = logical_line - display_start;
                Gutter {
                    before_line: Some(before_start + offset),
                    after_line: Some(after_start + offset),
                    marker: None,
                }
            }
        }
    }
}

fn side_line_gutter(side: usize, logical_line: usize, change: DiffLineKind) -> Gutter {
    let marker = match change {
        DiffLineKind::Context => None,
        DiffLineKind::Add => Some('+'),
        DiffLineKind::Remove => Some('-'),
    };

    match side {
        BEFORE_SIDE => Gutter {
            before_line: Some(logical_line),
            after_line: None,
            marker,
        },
        AFTER_SIDE => Gutter {
            before_line: None,
            after_line: Some(logical_line),
            marker,
        },
        _ => Gutter {
            before_line: None,
            after_line: None,
            marker,
        },
    }
}

impl WrappedSide {
    fn visual_segments(&self, logical_line: usize) -> &[WrappedSegment] {
        self.visual_segments_by_line
            .get(logical_line)
            .unwrap_or_else(|| panic!("logical line {logical_line} is outside wrapped side"))
    }
}

fn wrap_all_sides(model: &DiffModel, width: usize) -> Vec<WrappedSide> {
    model
        .sides()
        .iter()
        .map(|side| wrap_side(side, width))
        .collect()
}

fn wrap_sides_by_widths(model: &DiffModel, widths: &[usize]) -> Vec<WrappedSide> {
    assert_eq!(
        model.sides().len(),
        2,
        "side-by-side projection requires a two-side diff model"
    );
    assert_eq!(
        widths.len(),
        model.sides().len(),
        "side widths must match model sides"
    );

    model
        .sides()
        .iter()
        .zip(widths.iter().copied())
        .map(|(side, width)| wrap_side(side, width))
        .collect()
}

fn wrap_side(side: &SideDoc, width: usize) -> WrappedSide {
    let mut generator = SnapshotGenerator::from_text(side.text(), width);
    generator.set_viewport_width(width);
    let grid = generator.get_headless_grid(0, usize::MAX);
    let mut visual_segments_by_line = vec![Vec::new(); side.line_count()];

    for headless_line in grid.lines {
        if let Some(segments) = visual_segments_by_line.get_mut(headless_line.logical_line_index) {
            segments.push(WrappedSegment {
                visual_in_logical: headless_line.visual_in_logical,
                cells: headless_line.cells,
            });
        }
    }

    for (logical_line, segments) in visual_segments_by_line.iter().enumerate() {
        assert!(
            !segments.is_empty(),
            "SnapshotGenerator did not return visual segments for logical line {logical_line}"
        );
    }

    WrappedSide {
        visual_segments_by_line,
    }
}

fn push_line_rows(
    rows: &mut Vec<Row>,
    wrapped_sides: &[WrappedSide],
    side: usize,
    lines: &Range<usize>,
    change: DiffLineKind,
    gutter_mapping: GutterMapping,
) {
    let mut slots = Vec::new();
    push_line_slots(
        &mut slots,
        wrapped_sides,
        side,
        lines,
        change,
        gutter_mapping,
    );

    rows.extend(slots.into_iter().map(|slot| Row::new(vec![slot])));
}

fn push_line_slots(
    slots: &mut Vec<RowSlot>,
    wrapped_sides: &[WrappedSide],
    side: usize,
    lines: &Range<usize>,
    change: DiffLineKind,
    gutter_mapping: GutterMapping,
) {
    let wrapped_side = wrapped_sides
        .get(side)
        .unwrap_or_else(|| panic!("side {side} is outside wrapped sides"));

    for logical_line in lines.clone() {
        for segment in wrapped_side.visual_segments(logical_line) {
            let mut cells = segment.cells.clone();
            style::apply_diff_line_style(&mut cells, change);
            slots.push(RowSlot::Line {
                side,
                logical_line,
                visual_in_logical: segment.visual_in_logical,
                change,
                gutter: gutter_mapping.gutter(
                    side,
                    logical_line,
                    segment.visual_in_logical,
                    change,
                ),
                cells,
            });
        }
    }
}

fn push_side_by_side_unit(
    columns: &mut [Vec<RowSlot>; 2],
    wrapped_sides: &[WrappedSide],
    unit: &AlignUnit,
) -> [DiffLineKind; 2] {
    match unit {
        AlignUnit::Context { sides } => {
            assert!(
                sides.len() >= 2,
                "context alignment units require before and after sides"
            );
            for side in [BEFORE_SIDE, AFTER_SIDE] {
                push_line_slots(
                    &mut columns[side],
                    wrapped_sides,
                    side,
                    &sides[side],
                    DiffLineKind::Context,
                    GutterMapping::SideLine,
                );
            }
            [DiffLineKind::Context, DiffLineKind::Context]
        }
        AlignUnit::Replace { sides } => {
            assert!(
                sides.len() >= 2,
                "replace alignment units require before and after sides"
            );
            push_line_slots(
                &mut columns[BEFORE_SIDE],
                wrapped_sides,
                BEFORE_SIDE,
                &sides[BEFORE_SIDE],
                DiffLineKind::Remove,
                GutterMapping::SideLine,
            );
            push_line_slots(
                &mut columns[AFTER_SIDE],
                wrapped_sides,
                AFTER_SIDE,
                &sides[AFTER_SIDE],
                DiffLineKind::Add,
                GutterMapping::SideLine,
            );
            [DiffLineKind::Remove, DiffLineKind::Add]
        }
        AlignUnit::Add { side, lines } => {
            assert!(
                *side < 2,
                "add alignment side is outside side-by-side columns"
            );
            push_line_slots(
                &mut columns[*side],
                wrapped_sides,
                *side,
                lines,
                DiffLineKind::Add,
                GutterMapping::SideLine,
            );
            [DiffLineKind::Add, DiffLineKind::Add]
        }
        AlignUnit::Remove { side, lines } => {
            assert!(
                *side < 2,
                "remove alignment side is outside side-by-side columns"
            );
            push_line_slots(
                &mut columns[*side],
                wrapped_sides,
                *side,
                lines,
                DiffLineKind::Remove,
                GutterMapping::SideLine,
            );
            [DiffLineKind::Remove, DiffLineKind::Remove]
        }
    }
}

fn push_aligned_unit_rows(
    rows: &mut Vec<Row>,
    mut columns: [Vec<RowSlot>; 2],
    spacer_changes: [DiffLineKind; 2],
) {
    let unit_height = columns.iter().map(Vec::len).max().unwrap_or(0);
    for (side, slots) in columns.iter_mut().enumerate() {
        slots.resize_with(unit_height, || RowSlot::Spacer {
            change: spacer_changes[side],
            gutter: Gutter::empty(),
            cells: style::diff_spacer_cells(),
        });
    }

    let [before_slots, after_slots] = columns;
    for (before_slot, after_slot) in before_slots.into_iter().zip(after_slots) {
        rows.push(Row::new(vec![before_slot, after_slot]));
    }
}
