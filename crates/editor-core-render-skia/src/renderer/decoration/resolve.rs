mod strikethrough;
mod underline;

use super::super::style::*;
use super::super::*;
use super::run::LineDecorationKind;
use strikethrough::resolve_strikethrough_decoration;
use underline::resolve_underline_decoration;

#[derive(Debug, Clone, Copy, Default)]
pub(in crate::renderer) struct ResolvedCellLineDecorations {
    /// Underline-like decoration (single/double/squiggly) and its resolved color.
    pub(in crate::renderer) underline: Option<(LineDecorationKind, Rgba8)>,
    /// Strikethrough color (if enabled).
    pub(in crate::renderer) strikethrough: Option<Rgba8>,
}

pub(in crate::renderer) fn resolve_cell_line_decorations(
    style_ids: &[u32],
    theme: &RenderTheme,
    resolved_cell_fg: Rgba8,
) -> ResolvedCellLineDecorations {
    ResolvedCellLineDecorations {
        underline: resolve_underline_decoration(style_ids, theme, resolved_cell_fg),
        strikethrough: resolve_strikethrough_decoration(style_ids, theme, resolved_cell_fg),
    }
}
