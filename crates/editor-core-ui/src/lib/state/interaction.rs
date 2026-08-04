use crate::prelude::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MarkedRange {
    pub(crate) start: usize,
    pub(crate) len: usize,
    /// Text that was replaced when the IME composition started.
    ///
    /// Needed to support "cancel composition" without losing the original selection.
    pub(crate) original_text: String,
    pub(crate) original_len: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SearchQueryState {
    pub(crate) query: String,
    pub(crate) options: SearchOptions,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MouseSelectionMode {
    Char,
    Word,
    Line,
    Paragraph,
    Rect,
}

#[derive(Debug, Clone)]
pub(crate) struct MouseDragState {
    pub(crate) mode: MouseSelectionMode,
    pub(crate) anchor_pos: Position,
    pub(crate) anchor_offset: usize,
    /// For unit-based selections (word), store the initial selected unit range.
    pub(crate) anchor_unit_range: Option<(usize, usize)>,
}
