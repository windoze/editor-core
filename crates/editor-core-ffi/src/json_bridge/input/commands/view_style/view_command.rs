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
    pub(crate) fn try_into_core(self) -> Result<ViewCommand, String> {
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
