use super::*;

pub(in crate::renderer) fn make_shaper_feature(tag: FourByteTag, value: u32) -> Feature {
    Feature {
        tag: *tag,
        value,
        start: 0,
        end: usize::MAX,
    }
}
