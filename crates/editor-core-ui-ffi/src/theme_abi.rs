use editor_core_render_skia::{
    RenderTheme, Rgba8, StyleColors, StyleFont, TextDecorations, UnderlineStyle,
};
use editor_core_ui::ChromeTheme;
use std::collections::BTreeMap;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuRgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuTheme {
    pub background: EcuRgba8,
    pub foreground: EcuRgba8,
    pub selection_background: EcuRgba8,
    pub caret: EcuRgba8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuChromeTheme {
    pub gutter_background: EcuRgba8,
    pub gutter_foreground: EcuRgba8,
    pub gutter_separator: EcuRgba8,
    pub fold_marker_collapsed: EcuRgba8,
    pub fold_marker_expanded: EcuRgba8,
}

/// A single `StyleId` override entry.
///
/// `flags` is a bitmask:
/// - bit 0: foreground is present
/// - bit 1: background is present
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleColors {
    pub style_id: u32,
    pub flags: u32,
    pub foreground: EcuRgba8,
    pub background: EcuRgba8,
}

/// A single `StyleId` text-decoration override entry (underline/strikethrough).
///
/// `flags` is a bitmask:
/// - bit 0: underline style is present
/// - bit 1: underline color is present
/// - bit 2: strikethrough is present
/// - bit 3: strikethrough color is present
///
/// `underline_style` values:
/// - 1: single underline
/// - 2: double underline
/// - 3: squiggly underline
///
/// `strikethrough` values:
/// - 0: disabled
/// - 1: enabled
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleTextDecorations {
    pub style_id: u32,
    pub flags: u32,
    pub underline_style: u32,
    pub underline_color: EcuRgba8,
    pub strikethrough: u32,
    pub strikethrough_color: EcuRgba8,
}

/// A single StyleId font-style override entry.
///
/// flags bitmask:
/// - bit 0: bold present
/// - bit 1: italic present
///
/// Values:
/// - bold: 0=disabled, 1=enabled
/// - italic: 0=disabled, 1=enabled
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleFont {
    pub style_id: u32,
    pub flags: u32,
    pub bold: u32,
    pub italic: u32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuSelectionRange {
    pub start: u32,
    pub end: u32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuViewportState {
    pub width_cells: u32,
    pub height_rows: u32,
    pub has_height: u32,
    pub scroll_top: u32,
    pub sub_row_offset: u32,
    pub overscan_rows: u32,
    pub visible_start: u32,
    pub visible_end: u32,
    pub prefetch_start: u32,
    pub prefetch_end: u32,
    pub total_visual_lines: u32,
}

pub(crate) const ECU_STYLE_FLAG_FOREGROUND: u32 = 1 << 0;
pub(crate) const ECU_STYLE_FLAG_BACKGROUND: u32 = 1 << 1;

pub(crate) const ECU_TEXT_DECORATION_FLAG_UNDERLINE: u32 = 1 << 0;
pub(crate) const ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR: u32 = 1 << 1;
const ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH: u32 = 1 << 2;
const ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH_COLOR: u32 = 1 << 3;

const ECU_STYLE_FONT_FLAG_BOLD: u32 = 1 << 0;
const ECU_STYLE_FONT_FLAG_ITALIC: u32 = 1 << 1;

pub(crate) fn theme_from_ffi(theme: &EcuTheme) -> RenderTheme {
    RenderTheme {
        background: Rgba8::new(
            theme.background.r,
            theme.background.g,
            theme.background.b,
            theme.background.a,
        ),
        foreground: Rgba8::new(
            theme.foreground.r,
            theme.foreground.g,
            theme.foreground.b,
            theme.foreground.a,
        ),
        selection_background: Rgba8::new(
            theme.selection_background.r,
            theme.selection_background.g,
            theme.selection_background.b,
            theme.selection_background.a,
        ),
        caret: Rgba8::new(theme.caret.r, theme.caret.g, theme.caret.b, theme.caret.a),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    }
}

fn rgba8_from_ffi(c: EcuRgba8) -> Rgba8 {
    Rgba8::new(c.r, c.g, c.b, c.a)
}

pub(crate) fn chrome_theme_from_ffi(theme: &EcuChromeTheme) -> ChromeTheme {
    ChromeTheme {
        gutter_background: rgba8_from_ffi(theme.gutter_background),
        gutter_foreground: rgba8_from_ffi(theme.gutter_foreground),
        gutter_separator: rgba8_from_ffi(theme.gutter_separator),
        fold_marker_collapsed: rgba8_from_ffi(theme.fold_marker_collapsed),
        fold_marker_expanded: rgba8_from_ffi(theme.fold_marker_expanded),
    }
}

pub(crate) fn style_colors_from_ffi(entry: &EcuStyleColors) -> (u32, StyleColors) {
    let fg = if entry.flags & ECU_STYLE_FLAG_FOREGROUND != 0 {
        Some(Rgba8::new(
            entry.foreground.r,
            entry.foreground.g,
            entry.foreground.b,
            entry.foreground.a,
        ))
    } else {
        None
    };

    let bg = if entry.flags & ECU_STYLE_FLAG_BACKGROUND != 0 {
        Some(Rgba8::new(
            entry.background.r,
            entry.background.g,
            entry.background.b,
            entry.background.a,
        ))
    } else {
        None
    };

    (entry.style_id, StyleColors::new(fg, bg))
}

pub(crate) fn text_decorations_from_ffi(
    entry: &EcuStyleTextDecorations,
) -> Result<(u32, TextDecorations), String> {
    let mut out = TextDecorations::default();

    if entry.flags & ECU_TEXT_DECORATION_FLAG_UNDERLINE != 0 {
        let underline = match entry.underline_style {
            1 => UnderlineStyle::Single,
            2 => UnderlineStyle::Double,
            3 => UnderlineStyle::Squiggly,
            other => {
                return Err(format!(
                    "invalid underline_style {} for style_id=0x{:08X}",
                    other, entry.style_id
                ));
            }
        };
        out.underline = Some(underline);
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR != 0 {
        out.underline_color = Some(Rgba8::new(
            entry.underline_color.r,
            entry.underline_color.g,
            entry.underline_color.b,
            entry.underline_color.a,
        ));
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH != 0 {
        out.strikethrough = Some(entry.strikethrough != 0);
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH_COLOR != 0 {
        out.strikethrough_color = Some(Rgba8::new(
            entry.strikethrough_color.r,
            entry.strikethrough_color.g,
            entry.strikethrough_color.b,
            entry.strikethrough_color.a,
        ));
    }

    Ok((entry.style_id, out))
}

pub(crate) fn style_font_from_ffi(entry: &EcuStyleFont) -> (u32, StyleFont) {
    let mut out = StyleFont::default();
    if entry.flags & ECU_STYLE_FONT_FLAG_BOLD != 0 {
        out.bold = Some(entry.bold != 0);
    }
    if entry.flags & ECU_STYLE_FONT_FLAG_ITALIC != 0 {
        out.italic = Some(entry.italic != 0);
    }
    (entry.style_id, out)
}
