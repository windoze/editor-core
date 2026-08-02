use super::*;

pub(super) fn toggle_fold_region(
    ui: &mut EditorUi,
    start_line: usize,
    end_line: usize,
    is_collapsed: bool,
) -> Result<(), UiError> {
    if is_collapsed {
        ui.exec_core(Command::Style(StyleCommand::Unfold { start_line }))
            .map(|_| ())
    } else {
        ui.exec_core(Command::Style(StyleCommand::Fold {
            start_line,
            end_line,
        }))
        .map(|_| ())
    }
}
