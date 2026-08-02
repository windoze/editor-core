use super::LspResultSlot;
use crate::prelude::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LspClientRequest {
    Result { view: ViewId, slot: LspResultSlot },
    OnTypeFormatting { view: ViewId, version: u64 },
}
