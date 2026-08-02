#[path = "row_signatures/composed.rs"]
mod composed;
#[path = "row_signatures/headless.rs"]
mod headless;
#[path = "row_signatures/selection.rs"]
mod selection;

use super::*;

pub(crate) use composed::*;
pub(crate) use headless::*;

fn fold_marker_state_for_line(logical_line: u32, fold_markers: &[FoldMarker]) -> Option<bool> {
    fold_markers
        .iter()
        .find(|m| m.logical_line == logical_line)
        .map(|m| m.is_collapsed)
}
