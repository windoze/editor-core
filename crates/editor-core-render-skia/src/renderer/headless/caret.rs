use super::super::*;

pub(super) fn caret_in_row_range(caret: &VisualCaret, row_range: Option<(usize, usize)>) -> bool {
    let Some((row_start, row_end)) = row_range else {
        return true;
    };
    let row = caret.row as usize;
    row >= row_start && row < row_end
}
