use super::*;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiWrapMode {
    None,
    Char,
    Word,
}

impl From<FfiWrapMode> for WrapMode {
    fn from(value: FfiWrapMode) -> Self {
        match value {
            FfiWrapMode::None => WrapMode::None,
            FfiWrapMode::Char => WrapMode::Char,
            FfiWrapMode::Word => WrapMode::Word,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum FfiWrapIndent {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<FfiWrapIndent> for WrapIndent {
    fn from(value: FfiWrapIndent) -> Self {
        match value {
            FfiWrapIndent::None => WrapIndent::None,
            FfiWrapIndent::SameAsLineIndent => WrapIndent::SameAsLineIndent,
            FfiWrapIndent::FixedCells { cells } => WrapIndent::FixedCells(cells),
        }
    }
}
