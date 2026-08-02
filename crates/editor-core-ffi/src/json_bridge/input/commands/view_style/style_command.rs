use super::*;

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
    pub(crate) fn into_core(self) -> StyleCommand {
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
