//! Readonly column views over diff projections.

use editor_core::{Cell, Command, CommandError, CommandExecutor, CommandResult, EditorCore};
use editor_core_diff::DiffLineKind;

use crate::model::DiffModel;
use crate::projection::{DiffProjection, Gutter, RowSlot};

const READONLY_REJECTED_MESSAGE: &str = "readonly diff column view rejects mutating commands";

/// A single readonly column view over a shared diff projection.
pub struct DiffColumnView<'projection> {
    projection: &'projection DiffProjection,
    column: usize,
    side: usize,
    executor: CommandExecutor,
}

impl<'projection> DiffColumnView<'projection> {
    /// Builds a column view for one source side and one projected column.
    ///
    /// The backing editor's viewport width is taken from the projection's `column_widths[column]`,
    /// so this view's wrapping always matches the projected row axis. Passing an independent width
    /// (as an earlier API did) could silently desynchronize cursor/row mapping.
    pub fn new(
        model: &DiffModel,
        projection: &'projection DiffProjection,
        column: usize,
        side: usize,
    ) -> Self {
        let viewport_width = projection
            .column_width(column)
            .unwrap_or_else(|| panic!("column {column} is outside diff projection"));
        assert!(
            viewport_width > 0,
            "projection column width must be greater than zero"
        );
        let side_doc = model
            .side(side)
            .unwrap_or_else(|| panic!("side {side} is outside diff model"));

        Self {
            projection,
            column,
            side,
            executor: CommandExecutor::new(side_doc.text(), viewport_width),
        }
    }

    /// Returns the projected column index used by this view.
    pub fn column(&self) -> usize {
        self.column
    }

    /// Returns the model side whose readonly editor backs this view.
    pub fn side(&self) -> usize {
        self.side
    }

    /// Returns the shared diff projection referenced by this view.
    pub fn projection(&self) -> &DiffProjection {
        self.projection
    }

    /// Returns the readonly command executor for inspection.
    pub fn command_executor(&self) -> &CommandExecutor {
        &self.executor
    }

    /// Returns the readonly editor core for inspection.
    pub fn editor(&self) -> &EditorCore {
        self.executor.editor()
    }

    /// Returns the number of rows on the unified visual row axis.
    pub fn row_count(&self) -> usize {
        self.projection.rows().len()
    }

    /// Returns one projected row for this column.
    pub fn row(&self, unified_row: usize) -> Option<DiffColumnRow> {
        let slot = self
            .projection
            .rows()
            .get(unified_row)?
            .slots()
            .get(self.column)?;
        Some(DiffColumnRow::from_slot(slot))
    }

    /// Returns all projected rows for this column.
    pub fn rows(&self) -> Vec<DiffColumnRow> {
        (0..self.row_count())
            .filter_map(|row| self.row(row))
            .collect()
    }

    /// Executes a readonly-safe editor command against the backing side document.
    pub fn execute(&mut self, command: Command) -> Result<CommandResult, CommandError> {
        if command.is_mutating() {
            return Err(CommandError::Other(READONLY_REJECTED_MESSAGE.to_owned()));
        }

        self.executor.execute(command)
    }

    /// Maps this side's visual row to the shared unified row axis.
    pub fn unified_row_for_side_visual_row(&self, side_visual_row: usize) -> Option<usize> {
        self.projection
            .unified_row_for_side_visual_row(self.side, side_visual_row)
    }

    /// Maps a unified row to this side's visual row when this side has a real line there.
    pub fn side_visual_row_for_unified_row(&self, unified_row: usize) -> Option<usize> {
        self.projection
            .side_visual_row_for_unified_row(self.side, unified_row)
    }

    /// Returns the cursor row in this side's real visual coordinate space.
    pub fn cursor_side_visual_row(&self) -> Option<usize> {
        let cursor = self.editor().cursor_position();
        self.editor()
            .logical_position_to_visual(cursor.line, cursor.column)
            .map(|(visual_row, _)| visual_row)
    }

    /// Returns the cursor row on the shared unified axis, skipping spacer rows naturally.
    pub fn cursor_unified_row(&self) -> Option<usize> {
        self.unified_row_for_side_visual_row(self.cursor_side_visual_row()?)
    }
}

/// A projected row as exposed by a single [`DiffColumnView`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiffColumnRow {
    /// Cells to display for this row; spacer rows are intentionally empty.
    pub cells: Vec<Cell>,
    /// Gutter metadata for this row.
    pub gutter: Gutter,
    /// Source metadata for this projected row.
    pub source: DiffColumnRowSource,
}

impl DiffColumnRow {
    fn from_slot(slot: &RowSlot) -> Self {
        match slot {
            RowSlot::Line {
                side,
                logical_line,
                visual_in_logical,
                change,
                gutter,
                cells,
            } => Self {
                cells: cells.clone(),
                gutter: *gutter,
                source: DiffColumnRowSource::Line {
                    side: *side,
                    logical_line: *logical_line,
                    visual_in_logical: *visual_in_logical,
                    change: *change,
                },
            },
            RowSlot::Spacer { change, .. } => Self {
                cells: Vec::new(),
                gutter: Gutter::empty(),
                source: DiffColumnRowSource::Spacer { change: *change },
            },
        }
    }
}

/// Source metadata for a [`DiffColumnRow`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffColumnRowSource {
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
    },
    /// A filler row used only for unified-axis alignment.
    Spacer {
        /// Diff change kind for the alignment unit that owns this spacer.
        change: DiffLineKind,
    },
}
