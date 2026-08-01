use super::*;

impl EditorUi {
    pub fn add_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::AddStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn remove_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::RemoveStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Undo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Redo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn end_undo_group(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::EndUndoGroup))?;
        Ok(())
    }
}
