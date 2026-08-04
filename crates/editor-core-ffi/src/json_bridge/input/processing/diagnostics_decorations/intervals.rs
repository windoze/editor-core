use crate::*;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiIntervalInput {
    start: usize,
    end: usize,
    style_id: u32,
}

impl From<FfiIntervalInput> for Interval {
    fn from(value: FfiIntervalInput) -> Self {
        Interval::new(value.start, value.end, value.style_id)
    }
}
