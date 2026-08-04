use crate::*;
use editor_core::snapshot::{
    Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
    HeadlessGrid, HeadlessLine,
};
use std::collections::BTreeMap;

fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
    let idx = ((y * width_px + x) * 4) as usize;
    [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
}

fn marker_like_pixel(p: [u8; 4]) -> bool {
    p[0] > 80 && p[0] > p[1].saturating_add(30) && p[0] > p[2].saturating_add(30)
}

fn marker_pixel_count(
    buf: &[u8],
    width_px: u32,
    x_range: std::ops::Range<u32>,
    y_range: std::ops::Range<u32>,
) -> usize {
    let mut count = 0usize;
    for y in y_range {
        for x in x_range.clone() {
            if marker_like_pixel(pixel(buf, width_px, x, y)) {
                count += 1;
            }
        }
    }
    count
}

fn changed_pixel_count(
    a: &[u8],
    b: &[u8],
    width_px: u32,
    x_range: std::ops::Range<u32>,
    y_range: std::ops::Range<u32>,
) -> usize {
    let mut count = 0usize;
    for y in y_range {
        for x in x_range.clone() {
            if pixel(a, width_px, x, y) != pixel(b, width_px, x, y) {
                count += 1;
            }
        }
    }
    count
}

fn fold_marker_theme(marker: Rgba8, gutter_bg: Rgba8) -> RenderTheme {
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
        StyleColors::new(None, Some(gutter_bg)),
    );
    theme.styles.insert(
        GUTTER_FOREGROUND_STYLE_ID,
        StyleColors::new(Some(gutter_bg), None),
    );
    theme.styles.insert(
        FOLD_MARKER_COLLAPSED_STYLE_ID,
        StyleColors::new(Some(marker), None),
    );
    theme.styles.insert(
        FOLD_MARKER_EXPANDED_STYLE_ID,
        StyleColors::new(Some(marker), None),
    );
    theme
}

fn fold_marker_config(height_px: u32, style: FoldMarkerStyle) -> RenderConfig {
    RenderConfig {
        width_px: 80,
        height_px,
        scale: 1.0,
        font_size: 12.0,
        line_height_px: 20.0,
        text_vertical_align: TextVerticalAlign::Center,
        cell_width_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        scroll_y_px: 0.0,
        gutter_width_cells: 4,
        fold_marker_style: style,
        enable_ligatures: false,
        caret_width_px: 2.0,
        show_caret: false,
        ..RenderConfig::default()
    }
}

#[test]
fn render_draws_default_triangle_fold_markers_with_distinct_collapsed_and_expanded_shapes() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    for ch in [' ', ' '] {
        line.add_cell(Cell::new(ch, 1));
    }
    grid.add_line(line);

    let theme = fold_marker_theme(Rgba8::new(240, 20, 20, 255), Rgba8::new(1, 2, 3, 255));
    let cfg = fold_marker_config(20, FoldMarkerStyle::Triangle);

    let collapsed = renderer
        .render_rgba(
            &grid,
            &[],
            &[],
            &[FoldMarker {
                logical_line: 0,
                is_collapsed: true,
            }],
            cfg,
            &theme,
        )
        .unwrap();
    let expanded = renderer
        .render_rgba(
            &grid,
            &[],
            &[],
            &[FoldMarker {
                logical_line: 0,
                is_collapsed: false,
            }],
            cfg,
            &theme,
        )
        .unwrap();

    assert_ne!(
        collapsed, expanded,
        "collapsed `>` and expanded `v` fold marker rasters should differ"
    );
    assert!(
        marker_pixel_count(&collapsed, cfg.width_px, 0..20, 0..20) > 0,
        "collapsed marker should draw marker-colored pixels in the marker column"
    );
    assert!(
        marker_pixel_count(&expanded, cfg.width_px, 0..20, 0..20) > 0,
        "expanded marker should draw marker-colored pixels in the marker column"
    );
    assert!(
        changed_pixel_count(&collapsed, &expanded, cfg.width_px, 0..20, 0..20) > 0,
        "collapsed and expanded markers should differ inside the marker column"
    );
}

#[test]
fn render_hides_fold_markers_when_configured_hidden() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 1);
    let mut line = HeadlessLine::new(0, false);
    line.add_cell(Cell::new(' ', 1));
    grid.add_line(line);

    let theme = fold_marker_theme(Rgba8::new(240, 20, 20, 255), Rgba8::new(1, 2, 3, 255));
    let cfg = RenderConfig {
        width_px: 60,
        ..fold_marker_config(20, FoldMarkerStyle::Hidden)
    };

    let rgba = renderer
        .render_rgba(
            &grid,
            &[],
            &[],
            &[FoldMarker {
                logical_line: 0,
                is_collapsed: false,
            }],
            cfg,
            &theme,
        )
        .unwrap();

    assert_eq!(marker_pixel_count(&rgba, cfg.width_px, 0..20, 0..20), 0);
    assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [1, 2, 3, 255]);
}

#[test]
fn render_composed_draws_fold_marker_for_document_line_not_virtual_line() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = ComposedGrid::new(0, 2);
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::VirtualAboveLine { logical_line: 0 },
        char_offset_start: 0,
        char_offset_end: 0,
        cells: vec![ComposedCell {
            ch: ' ',
            width: 1,
            styles: Vec::new(),
            source: ComposedCellSource::Virtual { anchor_offset: 0 },
        }],
    });
    grid.lines.push(ComposedLine {
        kind: ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0,
        },
        char_offset_start: 0,
        char_offset_end: 1,
        cells: vec![ComposedCell {
            ch: ' ',
            width: 1,
            styles: Vec::new(),
            source: ComposedCellSource::Document { offset: 0 },
        }],
    });

    let theme = fold_marker_theme(Rgba8::new(240, 20, 20, 255), Rgba8::new(1, 2, 3, 255));
    let cfg = fold_marker_config(40, FoldMarkerStyle::Triangle);

    let mut out = vec![0u8; SkiaRenderer::required_rgba_len(cfg).unwrap()];
    renderer
        .render_composed_rgba_into(
            &grid,
            &[],
            &[],
            &[FoldMarker {
                logical_line: 0,
                is_collapsed: false,
            }],
            cfg,
            &theme,
            &mut out,
        )
        .unwrap();

    assert_eq!(marker_pixel_count(&out, cfg.width_px, 0..20, 0..20), 0);
    assert!(
        marker_pixel_count(&out, cfg.width_px, 0..20, 20..40) > 0,
        "document line should draw its fold marker even when preceded by virtual text"
    );
}

#[test]
fn render_partial_rows_matches_full_redraw_when_fold_marker_state_changes() {
    let mut renderer = SkiaRenderer::new();

    let mut grid = HeadlessGrid::new(0, 2);
    for logical_line in 0..2 {
        let mut line = HeadlessLine::new(logical_line, false);
        for ch in [' ', ' '] {
            line.add_cell(Cell::new(ch, 1));
        }
        grid.add_line(line);
    }

    let theme = fold_marker_theme(Rgba8::new(240, 20, 20, 255), Rgba8::new(1, 2, 3, 255));
    let cfg = fold_marker_config(40, FoldMarkerStyle::Triangle);

    let mut out = renderer
        .render_rgba(
            &grid,
            &[],
            &[],
            &[FoldMarker {
                logical_line: 0,
                is_collapsed: false,
            }],
            cfg,
            &theme,
        )
        .unwrap();

    let new_markers = [FoldMarker {
        logical_line: 0,
        is_collapsed: true,
    }];
    renderer
        .render_rgba_into_partial_rows(
            &grid,
            &[],
            &[],
            &new_markers,
            cfg,
            &theme,
            &mut out,
            &[(0, 1)],
        )
        .unwrap();

    let full_new = renderer
        .render_rgba(&grid, &[], &[], &new_markers, cfg, &theme)
        .unwrap();

    assert_eq!(out, full_new);
}
