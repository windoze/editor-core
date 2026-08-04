use skia_safe::shaper::RunHandler;
use skia_safe::shaper::run_handler::{Buffer, RunInfo};
use skia_safe::{GlyphId, Point};

#[derive(Default)]
pub(in crate::renderer) struct CollectGlyphsRunHandler {
    glyphs: Vec<GlyphId>,
    positions: Vec<Point>,
    clusters: Vec<u32>,
    pub(in crate::renderer) out_glyphs: Vec<GlyphId>,
    pub(in crate::renderer) out_clusters: Vec<u32>,
}

impl RunHandler for CollectGlyphsRunHandler {
    fn begin_line(&mut self) {}
    fn run_info(&mut self, _info: &RunInfo) {}
    fn commit_run_info(&mut self) {}

    fn run_buffer(&mut self, info: &RunInfo) -> Buffer<'_> {
        let count = info.glyph_count;
        self.glyphs.resize(count, GlyphId::default());
        self.positions.resize(count, Point::default());
        self.clusters.resize(count, 0);
        Buffer {
            glyphs: self.glyphs.as_mut_slice(),
            positions: self.positions.as_mut_slice(),
            offsets: None,
            clusters: Some(self.clusters.as_mut_slice()),
            point: Point::default(),
        }
    }

    fn commit_run_buffer(&mut self, _info: &RunInfo) {
        self.out_glyphs.extend_from_slice(&self.glyphs);
        self.out_clusters.extend_from_slice(&self.clusters);
    }

    fn commit_line(&mut self) {}
}
