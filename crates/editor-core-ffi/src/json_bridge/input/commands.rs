mod cursor;
mod edit;
mod view_style;

use super::super::*;
use super::primitives::*;

pub(crate) use cursor::*;
pub(crate) use edit::*;
pub(crate) use view_style::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiCommandInput {
    Edit {
        #[serde(flatten)]
        op: FfiEditCommandInput,
    },
    Cursor {
        #[serde(flatten)]
        op: FfiCursorCommandInput,
    },
    View {
        #[serde(flatten)]
        op: FfiViewCommandInput,
    },
    Style {
        #[serde(flatten)]
        op: FfiStyleCommandInput,
    },
}

impl FfiCommandInput {
    pub(crate) fn into_core(self) -> Result<Command, String> {
        Ok(match self {
            Self::Edit { op } => Command::Edit(op.try_into_core()?),
            Self::Cursor { op } => Command::Cursor(op.into_core()),
            Self::View { op } => Command::View(op.try_into_core()?),
            Self::Style { op } => Command::Style(op.into_core()),
        })
    }
}
