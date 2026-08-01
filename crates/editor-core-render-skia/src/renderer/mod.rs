mod composed;
mod decoration;
mod drawing;
mod font;
mod font_loading;
mod geometry;
mod headless;
mod metal;
mod state;
mod style;
mod text_runs;

pub(crate) use font::FontVariant;
use font::{FontSet, ShapedRunCache};
#[cfg(test)]
pub(crate) use font_loading::{make_configured_font, normalize_font_family_name};
#[cfg(target_os = "macos")]
use state::SkiaMetalState;
pub use state::SkiaRenderer;

use super::*;
use editor_core::{
    DOCUMENT_LINK_STYLE_ID, IME_MARKED_TEXT_STYLE_ID,
    snapshot::{
        ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
        HeadlessGrid,
    },
};
use skia_safe::Shaper;
use skia_safe::shaper::run_handler::{Buffer, RunInfo};
use skia_safe::shaper::{Feature, RunHandler};
use skia_safe::{
    AlphaType, Color, ColorSpace, ColorType, Font, FontHinting, FontMgr, FontStyle, FourByteTag,
    GlyphId, ImageInfo, Paint, Point, Rect, surfaces,
};
use std::collections::{HashMap, VecDeque};
use std::ffi::c_void;

#[cfg(target_os = "macos")]
use skia_safe::gpu;
