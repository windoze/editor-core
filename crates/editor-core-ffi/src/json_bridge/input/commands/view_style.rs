use super::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiViewCommandInput {
    SetViewportWidth { width: usize },
    SetWrapMode { mode: FfiWrapMode },
    SetWrapIndent { indent: FfiWrapIndent },
    SetTabWidth { width: usize },
    SetTabKeyBehavior { behavior: FfiTabKeyBehavior },
    SetIndentationConfig { config: FfiIndentationConfig },
    SetAutoPairsConfig { config: FfiAutoPairsConfig },
    SetAutoPairsEnabled { enabled: bool },
    SetWordBoundaryAsciiBoundaryChars { boundary_chars: String },
    ResetWordBoundaryDefaults,
    ScrollTo { line: usize },
    GetViewport { start_row: usize, count: usize },
}

impl FfiViewCommandInput {
    pub(super) fn try_into_core(self) -> Result<ViewCommand, String> {
        Ok(match self {
            Self::SetViewportWidth { width } => ViewCommand::SetViewportWidth { width },
            Self::SetWrapMode { mode } => ViewCommand::SetWrapMode { mode: mode.into() },
            Self::SetWrapIndent { indent } => ViewCommand::SetWrapIndent {
                indent: indent.into(),
            },
            Self::SetTabWidth { width } => ViewCommand::SetTabWidth { width },
            Self::SetTabKeyBehavior { behavior } => ViewCommand::SetTabKeyBehavior {
                behavior: behavior.into(),
            },
            Self::SetIndentationConfig { config } => ViewCommand::SetIndentationConfig {
                config: config.into(),
            },
            Self::SetAutoPairsConfig { config } => ViewCommand::SetAutoPairsConfig {
                config: config.try_into_core()?,
            },
            Self::SetAutoPairsEnabled { enabled } => ViewCommand::SetAutoPairsEnabled { enabled },
            Self::SetWordBoundaryAsciiBoundaryChars { boundary_chars } => {
                ViewCommand::SetWordBoundaryAsciiBoundaryChars { boundary_chars }
            }
            Self::ResetWordBoundaryDefaults => ViewCommand::ResetWordBoundaryDefaults,
            Self::ScrollTo { line } => ViewCommand::ScrollTo { line },
            Self::GetViewport { start_row, count } => ViewCommand::GetViewport { start_row, count },
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiStyleCommandInput {
    AddStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    RemoveStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    Fold {
        start_line: usize,
        end_line: usize,
    },
    Unfold {
        start_line: usize,
    },
    UnfoldAll,
    UpdateBracketMatchHighlights,
    ClearBracketMatchHighlights,
}

impl FfiStyleCommandInput {
    pub(super) fn into_core(self) -> StyleCommand {
        match self {
            Self::AddStyle {
                start,
                end,
                style_id,
            } => StyleCommand::AddStyle {
                start,
                end,
                style_id,
            },
            Self::RemoveStyle {
                start,
                end,
                style_id,
            } => StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            },
            Self::Fold {
                start_line,
                end_line,
            } => StyleCommand::Fold {
                start_line,
                end_line,
            },
            Self::Unfold { start_line } => StyleCommand::Unfold { start_line },
            Self::UnfoldAll => StyleCommand::UnfoldAll,
            Self::UpdateBracketMatchHighlights => StyleCommand::UpdateBracketMatchHighlights,
            Self::ClearBracketMatchHighlights => StyleCommand::ClearBracketMatchHighlights,
        }
    }
}
