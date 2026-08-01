use super::*;
use editor_core::snapshot::{
    Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
    HeadlessGrid, HeadlessLine,
};
use skia_safe::TextBlobIter;
use skia_safe::shaper::TextBlobBuilderRunHandler;

#[test]
fn normalize_font_family_name_strips_quotes() {
    assert_eq!(normalize_font_family_name("Menlo"), "Menlo");
    assert_eq!(normalize_font_family_name(" \"Menlo\" "), "Menlo");
    assert_eq!(normalize_font_family_name("'Menlo'"), "Menlo");
}

#[test]
fn fold_marker_style_default_is_vscode_arrows() {
    assert_eq!(FoldMarkerStyle::default(), FoldMarkerStyle::Triangle);
}

#[test]
fn set_font_families_unknown_still_renders_via_fallback() {
    let mut renderer = SkiaRenderer::new();
    renderer.set_font_families(vec!["ThisFontShouldNotExist-xyz".to_string()]);

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    line.add_cell(Cell::new('a', 1));
    grid.add_line(line);

    let cfg = RenderConfig {
        width_px: 40,
        height_px: 40,
        scale: 1.0,
        font_size: 20.0,
        line_height_px: 40.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let _ = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &RenderTheme::default())
        .unwrap();
}

#[test]
#[cfg(target_os = "macos")]
fn font_fallback_picks_second_family_for_cjk_when_first_missing() {
    let mgr = FontMgr::new();
    let style = FontStyle::normal();

    if mgr.match_family_style("Menlo", style).is_none()
        || mgr.match_family_style("PingFang SC", style).is_none()
    {
        // Some minimal macOS environments might not ship all fonts.
        return;
    }

    let mut renderer = SkiaRenderer::new();
    renderer.set_font_families(vec!["Menlo".to_string(), "PingFang SC".to_string()]);
    assert!(renderer.fonts_normal.fonts.len() >= 2);

    // Menlo should not have glyph for '你', so the renderer must fall back to PingFang.
    assert_eq!(renderer.font_index_for_char('你', FontVariant::Normal), 1);
}

#[test]
fn render_draws_some_text_pixels() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    line.add_cell(Cell::new('M', 1));
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: Rgba8::new(250, 250, 250, 255),
        // Make selection/caret invisible so only text can affect pixels.
        selection_background: bg,
        caret: bg,
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 40,
        height_px: 40,
        scale: 1.0,
        font_size: 20.0,
        line_height_px: 40.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();

    let bg_px = [bg.r, bg.g, bg.b, bg.a];
    assert!(
        rgba.chunks_exact(4).any(|p| p != bg_px),
        "expected at least one non-background pixel from glyph rendering"
    );
}

#[test]
fn metal_enable_rejects_null_handles() {
    let mut renderer = SkiaRenderer::new();
    let result = renderer.enable_metal(std::ptr::null_mut(), std::ptr::null_mut());

    if cfg!(target_os = "macos") {
        assert!(matches!(result, Err(RenderError::MetalInvalidHandle)));
    } else {
        assert!(matches!(result, Err(RenderError::MetalUnsupported)));
    }
}

#[test]
fn render_draws_ime_marked_underline_even_for_space() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    cell.styles.push(IME_MARKED_TEXT_STYLE_ID);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let fg = Rgba8::new(250, 250, 250, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: fg,
        selection_background: bg,
        caret: bg,
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let bytes_per_row = cfg.width_px as usize * 4;
    let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
    assert_eq!(&rgba[idx..idx + 4], &[fg.r, fg.g, fg.b, fg.a]);
}

#[test]
fn render_draws_lsp_diagnostics_underline_even_for_space() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    // LSP diagnostics style id encoding: 0x0400_0100 | severity.
    cell.styles.push(0x0400_0100 | 1);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let diag = Rgba8::new(1, 200, 2, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: bg,
        caret: bg,
        styles: {
            let mut m = BTreeMap::new();
            m.insert(0x0400_0100 | 1, StyleColors::new(Some(diag), None));
            m
        },
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let bytes_per_row = cfg.width_px as usize * 4;
    let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
    assert_eq!(&rgba[idx..idx + 4], &[diag.r, diag.g, diag.b, diag.a]);
}

#[test]
fn render_draws_document_link_underline_even_for_space() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    cell.styles.push(DOCUMENT_LINK_STYLE_ID);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let link = Rgba8::new(1, 200, 2, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: bg,
        caret: bg,
        styles: {
            let mut m = BTreeMap::new();
            m.insert(DOCUMENT_LINK_STYLE_ID, StyleColors::new(Some(link), None));
            m
        },
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let bytes_per_row = cfg.width_px as usize * 4;
    let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
    assert_eq!(&rgba[idx..idx + 4], &[link.r, link.g, link.b, link.a]);
}

#[test]
fn render_draws_double_underline_from_theme_text_decorations() {
    let mut renderer = SkiaRenderer::new();

    let style_id = 42u32;

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    cell.styles.push(style_id);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let deco = Rgba8::new(1, 200, 2, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: bg, // keep glyphs invisible (space anyway)
        selection_background: bg,
        caret: bg,
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: {
            let mut m = BTreeMap::new();
            m.insert(
                style_id,
                TextDecorations {
                    underline: Some(UnderlineStyle::Double),
                    underline_color: Some(deco),
                    ..TextDecorations::default()
                },
            );
            m
        },
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let bytes_per_row = cfg.width_px as usize * 4;

    let idx_bottom = 9 * bytes_per_row + 5 * 4; // y=9 (bottom underline), x=5
    assert_eq!(
        &rgba[idx_bottom..idx_bottom + 4],
        &[deco.r, deco.g, deco.b, deco.a]
    );

    let idx_top = 7 * bytes_per_row + 5 * 4; // y=7 (second underline), x=5
    assert_eq!(
        &rgba[idx_top..idx_top + 4],
        &[deco.r, deco.g, deco.b, deco.a]
    );
}

#[test]
fn render_draws_squiggly_underline_from_theme_text_decorations() {
    let mut renderer = SkiaRenderer::new();

    let style_id = 42u32;

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    cell.styles.push(style_id);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let deco = Rgba8::new(1, 200, 2, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: bg,
        selection_background: bg,
        caret: bg,
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: {
            let mut m = BTreeMap::new();
            m.insert(
                style_id,
                TextDecorations {
                    underline: Some(UnderlineStyle::Squiggly),
                    underline_color: Some(deco),
                    ..TextDecorations::default()
                },
            );
            m
        },
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let bytes_per_row = cfg.width_px as usize * 4;

    // Squiggle alternates between y=9 and y=8 with a 2px segment width (scale=1).
    let idx_bottom = 9 * bytes_per_row + 4; // x=1 inside first bottom segment
    assert_eq!(
        &rgba[idx_bottom..idx_bottom + 4],
        &[deco.r, deco.g, deco.b, deco.a]
    );

    let idx_upper = 8 * bytes_per_row + 3 * 4; // x=3 inside the second (upper) segment
    assert_eq!(
        &rgba[idx_upper..idx_upper + 4],
        &[deco.r, deco.g, deco.b, deco.a]
    );
}

#[test]
fn render_draws_strikethrough_from_theme_text_decorations() {
    let mut renderer = SkiaRenderer::new();

    let style_id = 42u32;

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    let mut cell = Cell::new(' ', 1);
    cell.styles.push(style_id);
    line.add_cell(cell);
    grid.add_line(line);

    let bg = Rgba8::new(10, 20, 30, 255);
    let deco = Rgba8::new(1, 200, 2, 255);
    let theme = RenderTheme {
        background: bg,
        foreground: bg,
        selection_background: bg,
        caret: bg,
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: {
            let mut m = BTreeMap::new();
            m.insert(
                style_id,
                TextDecorations {
                    strikethrough: Some(true),
                    strikethrough_color: Some(deco),
                    ..TextDecorations::default()
                },
            );
            m
        },
    };

    let cfg = RenderConfig {
        width_px: 20,
        height_px: 10,
        scale: 1.0,
        font_size: 10.0,
        line_height_px: 10.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();
    let deco_px = [deco.r, deco.g, deco.b, deco.a];
    assert!(
        rgba.chunks_exact(4).any(|p| p == deco_px),
        "expected at least one strikethrough pixel"
    );
}

#[test]
fn render_rejects_zero_size() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    line.add_cell(Cell::new('a', 1));
    grid.add_line(line);

    let err = renderer
        .render_rgba(
            &grid,
            &[VisualCaret { row: 0, x_cells: 0 }],
            &[],
            &[],
            RenderConfig {
                width_px: 0,
                height_px: 10,
                ..RenderConfig::default()
            },
            &RenderTheme::default(),
        )
        .unwrap_err();
    assert!(matches!(err, RenderError::InvalidSize { .. }));
}

#[test]
fn render_fills_background_and_draws_selection_and_caret() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    // Use spaces so text glyph rasterization does not affect selection/caret pixel assertions.
    line.add_cell(Cell::new(' ', 1));
    line.add_cell(Cell::new(' ', 1));
    line.add_cell(Cell::new(' ', 1));
    grid.add_line(line);

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(
            &grid,
            &[VisualCaret { row: 0, x_cells: 3 }],
            &[VisualSelection {
                start_row: 0,
                start_x_cells: 0,
                end_row: 0,
                end_x_cells: 2,
            }],
            &[],
            cfg,
            &theme,
        )
        .unwrap();

    assert_eq!(rgba.len(), (cfg.width_px * cfg.height_px * 4) as usize);

    // Background at (70, 30) should be background color (no selection/caret there).
    assert_eq!(pixel(&rgba, cfg.width_px, 70, 30), [10, 20, 30, 255]);

    // Selection area should be selection color.
    assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [200, 0, 0, 255]);

    // Caret should be caret color (x=30, y=10).
    assert_eq!(pixel(&rgba, cfg.width_px, 30, 10), [0, 0, 200, 255]);
}

#[test]
fn render_partial_rows_matches_full_redraw_headless() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 2);
    for line_idx in 0..2 {
        let mut line = HeadlessLine::new(line_idx, false);
        line.add_cell(Cell::new(' ', 1));
        line.add_cell(Cell::new(' ', 1));
        line.add_cell(Cell::new(' ', 1));
        grid.add_line(line);
    }

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let old_carets = [VisualCaret { row: 0, x_cells: 1 }];
    let old_selections = [VisualSelection {
        start_row: 0,
        start_x_cells: 0,
        end_row: 0,
        end_x_cells: 2,
    }];

    let new_carets = [VisualCaret { row: 1, x_cells: 1 }];
    let new_selections = [VisualSelection {
        start_row: 1,
        start_x_cells: 0,
        end_row: 1,
        end_x_cells: 2,
    }];

    let mut out = renderer
        .render_rgba(
            &grid,
            old_carets.as_slice(),
            old_selections.as_slice(),
            &[],
            cfg,
            &theme,
        )
        .unwrap();

    renderer
        .render_rgba_into_partial_rows(
            &grid,
            new_carets.as_slice(),
            new_selections.as_slice(),
            &[],
            cfg,
            &theme,
            &mut out,
            &[(0, 2)],
        )
        .unwrap();

    let full_new = renderer
        .render_rgba(
            &grid,
            new_carets.as_slice(),
            new_selections.as_slice(),
            &[],
            cfg,
            &theme,
        )
        .unwrap();

    assert_eq!(out, full_new);
}

#[test]
fn render_partial_rows_matches_full_redraw_composed() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = ComposedGrid::new(0, 2);
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0,
        },
        char_offset_start: 0,
        char_offset_end: 3,
        cells: vec![
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 0 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 1 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 2 },
            },
        ],
    });
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 1,
            visual_in_logical: 0,
        },
        char_offset_start: 3,
        char_offset_end: 6,
        cells: vec![
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 3 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 4 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 5 },
            },
        ],
    });

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let old_carets = [0usize];
    let old_selections = [(0usize, 2usize)];

    let new_carets = [3usize];
    let new_selections = [(3usize, 5usize)];

    let required = SkiaRenderer::required_rgba_len(cfg).unwrap();
    let mut out = vec![0u8; required];
    renderer
        .render_composed_rgba_into(
            &grid,
            old_carets.as_slice(),
            old_selections.as_slice(),
            &[],
            cfg,
            &theme,
            &mut out,
        )
        .unwrap();

    renderer
        .render_composed_rgba_into_partial_rows(
            &grid,
            new_carets.as_slice(),
            new_selections.as_slice(),
            &[],
            cfg,
            &theme,
            &mut out,
            &[(0, 2)],
        )
        .unwrap();

    let mut full_new = vec![0u8; required];
    renderer
        .render_composed_rgba_into(
            &grid,
            new_carets.as_slice(),
            new_selections.as_slice(),
            &[],
            cfg,
            &theme,
            &mut full_new,
        )
        .unwrap();

    assert_eq!(out, full_new);
}

#[test]
fn render_applies_style_background_overrides() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    // Use a space so glyph rasterization does not affect the background override pixel sample.
    line.add_cell(Cell::new('a', 1));
    line.add_cell(Cell::with_styles(' ', 1, vec![42]));
    line.add_cell(Cell::new('c', 1));
    grid.add_line(line);

    let mut theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };
    theme
        .styles
        .insert(42, StyleColors::new(None, Some(Rgba8::new(1, 200, 2, 255))));

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &theme)
        .unwrap();

    // Cell 'b' is at x in [10..20], pick center pixel.
    assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [1, 200, 2, 255]);
}

#[test]
fn render_selection_overrides_style_background() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    // Use a styled space so glyph rasterization does not affect the background pixel sample.
    line.add_cell(Cell::new('a', 1));
    line.add_cell(Cell::with_styles(' ', 1, vec![42]));
    line.add_cell(Cell::new('c', 1));
    grid.add_line(line);

    let mut theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(10, 20, 30, 255), // invisible
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };
    theme
        .styles
        .insert(42, StyleColors::new(None, Some(Rgba8::new(1, 200, 2, 255))));

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let rgba = renderer
        .render_rgba(
            &grid,
            &[],
            &[VisualSelection {
                start_row: 0,
                start_x_cells: 1,
                end_row: 0,
                end_x_cells: 2,
            }],
            &[],
            cfg,
            &theme,
        )
        .unwrap();

    // The styled cell would normally be green-ish, but selection must win.
    assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [200, 0, 0, 255]);
}

#[test]
fn render_composed_selection_overrides_style_background() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = ComposedGrid::new(0, 1);
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0,
        },
        char_offset_start: 0,
        char_offset_end: 3,
        cells: vec![
            ComposedCell {
                ch: 'a',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 0 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: vec![42],
                source: ComposedCellSource::Document { offset: 1 },
            },
            ComposedCell {
                ch: 'c',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 2 },
            },
        ],
    });

    let mut theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(10, 20, 30, 255), // invisible
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };
    theme
        .styles
        .insert(42, StyleColors::new(None, Some(Rgba8::new(1, 200, 2, 255))));

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
    renderer
        .render_composed_rgba_into(&grid, &[], &[(1, 2)], &[], cfg, &theme, &mut out)
        .unwrap();

    // Selected styled cell: x in [10..20], pick center pixel.
    assert_eq!(pixel(&out, cfg.width_px, 15, 10), [200, 0, 0, 255]);
}

#[test]
fn render_composed_selection_ignores_virtual_cells() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = ComposedGrid::new(0, 1);
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0,
        },
        char_offset_start: 0,
        char_offset_end: 1,
        cells: vec![
            // Virtual cell at offset 0 (e.g. inlay hint) - should NOT be selected.
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Virtual { anchor_offset: 0 },
            },
            // Document cell at offset 0 - should be selected for range 0..1.
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 0 },
            },
        ],
    });

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(10, 20, 30, 255), // invisible
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 40,
        height_px: 20,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
    renderer
        .render_composed_rgba_into(
            &grid,
            &[],
            &[(0, 1)], // select the single document char
            &[],
            cfg,
            &theme,
            out.as_mut_slice(),
        )
        .unwrap();

    // Virtual cell area (x in [0..20]) stays background.
    assert_eq!(pixel(&out, cfg.width_px, 10, 10), [10, 20, 30, 255]);

    // Document cell area (x in [20..40]) is selection color.
    assert_eq!(pixel(&out, cfg.width_px, 30, 10), [200, 0, 0, 255]);
}

#[test]
fn render_composed_caret_skips_wrap_indent_prefix() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = ComposedGrid::new(0, 1);
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 1, // wrapped segment
        },
        char_offset_start: 0,
        char_offset_end: 1,
        cells: vec![
            // Wrap indent (virtual, whitespace, no styles) - should be before caret.
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Virtual { anchor_offset: 0 },
            },
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Virtual { anchor_offset: 0 },
            },
            // First document char at offset 0.
            ComposedCell {
                ch: ' ',
                width: 1,
                styles: Vec::new(),
                source: ComposedCellSource::Document { offset: 0 },
            },
        ],
    });

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(10, 20, 30, 255), // invisible
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 60,
        height_px: 20,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
    renderer
        .render_composed_rgba_into(
            &grid,
            &[0], // caret at the segment start
            &[],
            &[],
            cfg,
            &theme,
            out.as_mut_slice(),
        )
        .unwrap();

    // Caret should be at x=40 (2 indent cells * 20px), y=10.
    assert_eq!(pixel(&out, cfg.width_px, 40, 10), [0, 0, 200, 255]);
}

fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
    let idx = ((y * width_px + x) * 4) as usize;
    [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
}

#[test]
fn render_draws_multiple_carets_and_selections() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    // Use spaces so glyph rasterization does not affect selection/caret pixel assertions.
    for ch in [' ', ' ', ' ', ' ', ' '] {
        line.add_cell(Cell::new(ch, 1));
    }
    grid.add_line(line);

    let theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };

    let cfg = RenderConfig {
        width_px: 120,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let carets = [
        VisualCaret { row: 0, x_cells: 1 },
        VisualCaret { row: 0, x_cells: 4 },
    ];
    let selections = [
        VisualSelection {
            start_row: 0,
            start_x_cells: 0,
            end_row: 0,
            end_x_cells: 1,
        },
        VisualSelection {
            start_row: 0,
            start_x_cells: 3,
            end_row: 0,
            end_x_cells: 5,
        },
    ];

    let rgba = renderer
        .render_rgba(&grid, &carets, &selections, &[], cfg, &theme)
        .unwrap();

    // Selection 1 should be red at x ~ 5.
    assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [200, 0, 0, 255]);
    // Selection 2 should be red at x ~ 35.
    assert_eq!(pixel(&rgba, cfg.width_px, 35, 10), [200, 0, 0, 255]);

    // Caret 1 at x=10.
    assert_eq!(pixel(&rgba, cfg.width_px, 10, 10), [0, 0, 200, 255]);
    // Caret 2 at x=40.
    assert_eq!(pixel(&rgba, cfg.width_px, 40, 10), [0, 0, 200, 255]);
}

#[test]
fn render_draws_gutter_and_fold_marker_and_offsets_text_overlays() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    // Use spaces so glyph rasterization does not affect selection/caret pixel assertions.
    for ch in [' ', ' ', ' '] {
        line.add_cell(Cell::new(ch, 1));
    }
    grid.add_line(line);

    let mut theme = RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(250, 250, 250, 255),
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    };
    theme.styles.insert(
        GUTTER_BACKGROUND_STYLE_ID,
        StyleColors::new(None, Some(Rgba8::new(1, 2, 3, 255))),
    );
    // Hide line number glyphs by matching the gutter background color.
    theme.styles.insert(
        GUTTER_FOREGROUND_STYLE_ID,
        StyleColors::new(Some(Rgba8::new(1, 2, 3, 255)), None),
    );
    theme.styles.insert(
        FOLD_MARKER_EXPANDED_STYLE_ID,
        StyleColors::new(None, Some(Rgba8::new(9, 9, 9, 255))),
    );

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        // Keep space for a 2-cell fold marker column + some line numbers.
        gutter_width_cells: 4,
        // Keep pixel assertions deterministic (chevrons are anti-aliased).
        fold_marker_style: FoldMarkerStyle::Block,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let carets = [VisualCaret { row: 0, x_cells: 2 }];
    let selections = [VisualSelection {
        start_row: 0,
        start_x_cells: 0,
        end_row: 0,
        end_x_cells: 1,
    }];
    let fold_markers = [FoldMarker {
        logical_line: 0,
        is_collapsed: false,
    }];

    let rgba = renderer
        .render_rgba(&grid, &carets, &selections, &fold_markers, cfg, &theme)
        .unwrap();

    // Fold marker fills first part of the gutter.
    assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [9, 9, 9, 255]);
    // Gutter background fills remaining gutter area.
    assert_eq!(pixel(&rgba, cfg.width_px, 25, 10), [1, 2, 3, 255]);

    // Selection should be offset by the gutter (text starts at x=40).
    assert_eq!(pixel(&rgba, cfg.width_px, 45, 10), [200, 0, 0, 255]);

    // Caret at x_cells=2 => x = 40 + 2*10 = 60.
    assert_eq!(pixel(&rgba, cfg.width_px, 60, 10), [0, 0, 200, 255]);
}

#[test]
fn render_rgba_into_rejects_too_small_output_buffer() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    line.add_cell(Cell::new('a', 1));
    grid.add_line(line);

    let cfg = RenderConfig {
        width_px: 80,
        height_px: 40,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let required = SkiaRenderer::required_rgba_len(cfg).unwrap();
    let mut out = vec![0u8; required.saturating_sub(1)];
    let err = renderer
        .render_rgba_into(
            &grid,
            &[],
            &[],
            &[],
            cfg,
            &RenderTheme::default(),
            out.as_mut_slice(),
        )
        .unwrap_err();
    assert!(matches!(err, RenderError::BufferTooSmall { .. }));
}

fn shape_glyph_count(shaper: &Shaper, text: &str, font: &Font, enable_ligatures: bool) -> usize {
    let features = SkiaRenderer::ligature_features(enable_ligatures);
    let width = 1_000_000.0;
    let utf8_len = text.len();

    let mut font_it = Shaper::new_trivial_font_run_iterator(font, utf8_len);
    let mut bidi_it = skia_safe::shapers::primitive::trivial_bidi_run_iterator(0, utf8_len);
    let mut script_it = skia_safe::shapers::primitive::trivial_script_run_iterator(0, utf8_len);
    let mut lang_it = Shaper::new_trivial_language_run_iterator("en", utf8_len);

    let mut builder = TextBlobBuilderRunHandler::new(text, Point::new(0.0, 0.0));
    shaper.shape_with_iterators_and_features(
        text,
        &mut font_it,
        &mut bidi_it,
        &mut script_it,
        &mut lang_it,
        features.as_ref(),
        width,
        &mut builder,
    );

    let Some(blob) = builder.make_blob() else {
        return 0;
    };

    TextBlobIter::new(&blob)
        .map(|run| run.glyph_indices.len())
        .sum()
}

#[test]
fn ligature_shaping_can_reduce_glyph_count_for_fi_in_some_system_font() {
    let mgr = FontMgr::new();
    let style = FontStyle::normal();

    // On macOS, at least one of these should exist and support `fi` ligatures.
    // We keep the list short to avoid enumerating all families.
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["Times New Roman", "Times", "Georgia", "Helvetica", "Arial"]
    } else if cfg!(target_os = "windows") {
        &["Times New Roman", "Georgia", "Arial"]
    } else {
        &["DejaVu Serif", "Liberation Serif", "Noto Serif"]
    };

    let shaper = Shaper::new(None);
    let mut found = false;
    for name in candidates {
        let Some(tf) = mgr.match_family_style(name, style) else {
            continue;
        };

        let font = make_configured_font(Some(tf), 32.0);
        let off = shape_glyph_count(&shaper, "fi", &font, false);
        let on = shape_glyph_count(&shaper, "fi", &font, true);

        if off > 0 && on > 0 && on < off {
            found = true;
            break;
        }
    }

    if cfg!(target_os = "macos") {
        // On macOS we expect at least one of the common serif fonts to exist and expose `fi`.
        assert!(
            found,
            "expected a system font where `fi` forms a ligature when enabled"
        );
    } else if !found {
        // Some minimal environments may not ship serif fonts with classic ligatures.
        // Keep this as a soft assertion so CI can still run headless.
        eprintln!("no candidate font produced a detectable 'fi' ligature; skipping hard assertion");
    }
}

#[test]
fn render_with_ligatures_enabled_smoke() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    for ch in "a->b != c".chars() {
        line.add_cell(Cell::new(ch, 1));
    }
    grid.add_line(line);

    let cfg = RenderConfig {
        width_px: 200,
        height_px: 40,
        scale: 1.0,
        font_size: 20.0,
        line_height_px: 40.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 0,
        enable_ligatures: true,
        caret_width_px: 2.0,
        show_caret: true,
        ..RenderConfig::default()
    };

    let _ = renderer
        .render_rgba(&grid, &[], &[], &[], cfg, &RenderTheme::default())
        .unwrap();
}
