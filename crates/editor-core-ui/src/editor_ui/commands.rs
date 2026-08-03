use super::*;

impl EditorUi {
    pub fn execute(&mut self, command: Command) -> Result<CommandResult, UiError> {
        let is_edit = matches!(command, Command::Edit(_));
        let result = self.exec_core(command)?;
        if is_edit {
            self.refresh_processing()?;
            self.ensure_primary_caret_visible_after_edit();
        }
        Ok(result)
    }

    /// Execute a core editor command encoded as JSON, using the same schema as the headless FFI
    /// command plane plus UI-specific additions such as snippets, auto-pairs config, and bracket
    /// highlight maintenance commands.
    pub fn execute_command_json(&mut self, command_json: &str) -> Result<String, UiError> {
        let command =
            command_json::parse_command_from_json(command_json).map_err(UiError::Processor)?;
        let is_edit = matches!(command, Command::Edit(_));
        let is_cursor = matches!(command, Command::Cursor(_));

        match &command {
            Command::View(ViewCommand::SetAutoPairsConfig { config }) => {
                self.auto_pairs = config.clone();
            }
            Command::View(ViewCommand::SetAutoPairsEnabled { enabled }) => {
                self.auto_pairs.enabled = *enabled;
            }
            _ => {}
        }

        let result = self.exec_core(command)?;

        if is_edit {
            self.refresh_processing()?;
            self.ensure_primary_caret_visible_after_edit();
        } else if is_cursor {
            self.ensure_primary_caret_visible_after_navigation();
        }

        serde_json::to_string(&command_json::command_result_to_value(result))
            .map_err(|err| UiError::Processor(format!("failed to encode command result: {err}")))
    }

    /// Enable/disable auto-pairs behavior for typed characters (`EditCommand::TypeChar`).
    ///
    /// Notes:
    /// - This is view-local (each `EditorUi` handle corresponds to one `Workspace` view).
    pub fn set_auto_pairs_enabled(&mut self, enabled: bool) -> Result<(), UiError> {
        self.auto_pairs.enabled = enabled;
        self.exec_core(Command::View(ViewCommand::SetAutoPairsConfig {
            config: self.auto_pairs.clone(),
        }))?;
        Ok(())
    }

    /// Enable/disable bracket-match highlighting.
    ///
    /// When enabled, the UI wrapper updates `StyleLayerId::BRACKET_MATCHES` after cursor moves and
    /// edits, so renderers can highlight the matching pair (if any).
    pub fn set_bracket_match_highlights_enabled(&mut self, enabled: bool) -> Result<(), UiError> {
        self.bracket_match_highlights_enabled = enabled;
        if enabled {
            let _ = self.exec_core(Command::Style(StyleCommand::UpdateBracketMatchHighlights));
        } else {
            let _ = self.exec_core(Command::Style(StyleCommand::ClearBracketMatchHighlights));
        }
        Ok(())
    }

    /// Enable/disable automatic LSP on-type formatting after trigger-character typing.
    ///
    /// This only controls the implicit typing path. Explicit `lsp_format_on_type(...)` requests
    /// remain available to hosts that intentionally invoke them.
    pub fn set_lsp_on_type_formatting_enabled(&mut self, enabled: bool) -> Result<(), UiError> {
        self.lsp_on_type_formatting_enabled = enabled;
        Ok(())
    }

    pub fn lsp_on_type_formatting_enabled(&self) -> bool {
        self.lsp_on_type_formatting_enabled
    }

    /// Jump the primary caret to the matching bracket (if any).
    pub fn move_to_matching_bracket(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveToMatchingBracket))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }
}
