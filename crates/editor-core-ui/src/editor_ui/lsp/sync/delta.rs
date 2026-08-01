use super::super::super::*;

impl EditorUi {
    pub(super) fn lsp_changes_for_text_delta(
        calc: &mut DeltaCalculator,
        delta: &editor_core::delta::TextDelta,
    ) -> Vec<LspContentChange> {
        let mut out = Vec::<LspContentChange>::with_capacity(delta.edits.len());
        for edit in &delta.edits {
            let (start_line, start_char) = position_for_char_offset(calc, edit.start);
            let (end_line, end_char) = position_for_char_offset(calc, edit.end());
            let change = calc.calculate_replace_change(
                start_line,
                start_char,
                end_line,
                end_char,
                edit.inserted_text.as_str(),
            );
            calc.apply_change(&change);
            out.push(LspContentChange {
                range: change.range,
                text: change.text,
            });
        }
        out
    }
}

fn position_for_char_offset(calc: &DeltaCalculator, mut offset: usize) -> (usize, usize) {
    let line_count = calc.line_count().max(1);
    for line in 0..line_count {
        let text = calc.get_line(line).unwrap_or("");
        let len = text.chars().count();
        if offset <= len {
            return (line, offset);
        }
        offset = offset.saturating_sub(len + 1);
    }

    let last_line = line_count.saturating_sub(1);
    let last_len = calc.get_line(last_line).unwrap_or("").chars().count();
    (last_line, last_len)
}
