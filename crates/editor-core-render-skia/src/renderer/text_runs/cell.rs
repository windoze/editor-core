use super::super::*;

pub(in crate::renderer) trait RenderTextCell {
    fn ch(&self) -> char;
    fn width(&self) -> usize;
    fn styles(&self) -> &[u32];
}

impl RenderTextCell for editor_core::snapshot::Cell {
    fn ch(&self) -> char {
        self.ch
    }

    fn width(&self) -> usize {
        self.width
    }

    fn styles(&self) -> &[u32] {
        self.styles.as_slice()
    }
}

impl RenderTextCell for ComposedCell {
    fn ch(&self) -> char {
        self.ch
    }

    fn width(&self) -> usize {
        self.width
    }

    fn styles(&self) -> &[u32] {
        self.styles.as_slice()
    }
}
