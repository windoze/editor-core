//! Diff-semantic style helpers for projected rows.

use editor_core::{Cell, StyleId};
use editor_core_diff::DiffLineKind;

pub use editor_core::{DIFF_ADD_LINE_STYLE_ID, DIFF_REMOVE_LINE_STYLE_ID, DIFF_SPACER_STYLE_ID};

/// Returns the row-level diff style for a real line segment, if any.
pub fn diff_line_style_id(change: DiffLineKind) -> Option<StyleId> {
    match change {
        DiffLineKind::Add => Some(DIFF_ADD_LINE_STYLE_ID),
        DiffLineKind::Remove => Some(DIFF_REMOVE_LINE_STYLE_ID),
        DiffLineKind::Context => None,
    }
}

/// Appends the row-level diff style to every existing cell without replacing other styles.
pub fn apply_diff_line_style(cells: &mut [Cell], change: DiffLineKind) {
    let Some(style_id) = diff_line_style_id(change) else {
        return;
    };

    for cell in cells {
        if !cell.styles.contains(&style_id) {
            cell.styles.push(style_id);
        }
    }
}

/// Builds the styled placeholder cells used for a spacer row.
pub fn diff_spacer_cells() -> Vec<Cell> {
    vec![Cell::with_styles(' ', 1, vec![DIFF_SPACER_STYLE_ID])]
}
