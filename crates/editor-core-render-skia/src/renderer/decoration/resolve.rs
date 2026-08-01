use super::super::style::*;
use super::super::*;
use super::run::LineDecorationKind;

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
    let diag_id = style_ids
        .iter()
        .copied()
        .find(|&id| is_lsp_diagnostics_style_id(id));

    // Underline candidate resolution:
    // - diagnostics > IME > document links > theme-defined underline on arbitrary style ids
    // - within the same priority bucket, later style ids win (to match color layering semantics)
    let mut best_underline: Option<(i32, usize, LineDecorationKind, Rgba8)> = None;

    let consider = |best: &mut Option<(i32, usize, LineDecorationKind, Rgba8)>,
                    priority: i32,
                    tie: usize,
                    kind: LineDecorationKind,
                    color: Rgba8| {
        let replace = match best {
            None => true,
            Some((p, t, _, _)) => priority > *p || (priority == *p && tie >= *t),
        };
        if replace {
            *best = Some((priority, tie, kind, color));
        }
    };

    if let Some(diag_id) = diag_id {
        let spec = theme
            .text_decorations
            .get(&diag_id)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = line_decoration_kind_for_underline_style(underline_style);
        let color = spec
            .underline_color
            .unwrap_or_else(|| resolve_underline_color(diag_id, theme, resolved_cell_fg));
        consider(&mut best_underline, 400, usize::MAX, kind, color);
    }

    if style_ids.contains(&IME_MARKED_TEXT_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&IME_MARKED_TEXT_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = line_decoration_kind_for_underline_style(underline_style);
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 300, usize::MAX, kind, color);
    }

    if style_ids.contains(&DOCUMENT_LINK_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&DOCUMENT_LINK_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = line_decoration_kind_for_underline_style(underline_style);
        let color = spec.underline_color.unwrap_or_else(|| {
            resolve_underline_color(DOCUMENT_LINK_STYLE_ID, theme, resolved_cell_fg)
        });
        consider(&mut best_underline, 200, usize::MAX, kind, color);
    }

    for (idx, &id) in style_ids.iter().enumerate() {
        if id == IME_MARKED_TEXT_STYLE_ID || id == DOCUMENT_LINK_STYLE_ID || diag_id == Some(id) {
            continue;
        }
        let spec = theme.text_decorations.get(&id).copied().or_else(|| {
            semantic_token_base_style_id(id)
                .and_then(|base| theme.text_decorations.get(&base).copied())
        });
        let Some(spec) = spec else { continue };
        let Some(underline_style) = spec.underline else {
            continue;
        };
        let kind = line_decoration_kind_for_underline_style(underline_style);
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 100, idx, kind, color);
    }

    let underline = best_underline.map(|(_p, _t, kind, color)| (kind, color));

    // Strikethrough: "last wins" by style-id order (independent of underline priority).
    let mut strike_enabled: bool = false;
    let mut strike_color: Option<Rgba8> = None;
    for &id in style_ids {
        let spec = theme.text_decorations.get(&id).copied().or_else(|| {
            semantic_token_base_style_id(id)
                .and_then(|base| theme.text_decorations.get(&base).copied())
        });
        let Some(spec) = spec else { continue };
        if let Some(v) = spec.strikethrough {
            strike_enabled = v;
        }
        if let Some(c) = spec.strikethrough_color {
            strike_color = Some(c);
        }
    }

    ResolvedCellLineDecorations {
        underline,
        strikethrough: strike_enabled.then(|| strike_color.unwrap_or(resolved_cell_fg)),
    }
}

fn line_decoration_kind_for_underline_style(style: UnderlineStyle) -> LineDecorationKind {
    match style {
        UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
        UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
        UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
    }
}
