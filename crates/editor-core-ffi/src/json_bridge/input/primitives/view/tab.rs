use super::*;

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FfiTabKeyBehavior {
    Tab,
    Spaces,
}

impl From<FfiTabKeyBehavior> for TabKeyBehavior {
    fn from(value: FfiTabKeyBehavior) -> Self {
        match value {
            FfiTabKeyBehavior::Tab => TabKeyBehavior::Tab,
            FfiTabKeyBehavior::Spaces => TabKeyBehavior::Spaces,
        }
    }
}
