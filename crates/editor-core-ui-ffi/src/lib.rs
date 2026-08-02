//! C ABI bridge for the editor UI component.
//!
//! This crate exposes a C ABI intended for native host UI toolkits.
//! The Rust side owns:
//! - editor state (`editor-core`)
//! - input mapping (`editor-core-ui`)
//! - rendering (Skia CPU raster in `editor-core-render-skia`)
//!
//! The host side is responsible for:
//! - OS window/view lifecycle
//! - event collection (IME/keyboard/mouse/scroll)
//! - presenting the rendered pixels (RGBA buffer) to screen

use editor_core::{ExpandSelectionDirection, ExpandSelectionUnit};
use editor_core_render_skia::{StyleColors, StyleFont, TextDecorations};
use editor_core_ui::{EditorUi, MultiDocumentEditorUi, TabId};
use libc::{c_char, c_float, c_int, c_void};
use std::collections::BTreeMap;
#[cfg(test)]
use std::ffi::CStr;
use std::ptr;

mod abi_features;
mod ffi_support;
mod theme_abi;

pub use abi_features::*;
pub use ffi_support::{editor_core_ui_ffi_last_error_message, editor_core_ui_ffi_string_free};
pub use theme_abi::*;

pub(crate) use ffi_support::*;
#[cfg(test)]
pub(crate) use theme_abi::{
    ECU_STYLE_FLAG_BACKGROUND, ECU_STYLE_FLAG_FOREGROUND, ECU_TEXT_DECORATION_FLAG_UNDERLINE,
    ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR,
};
pub(crate) use theme_abi::{
    chrome_theme_from_ffi, style_colors_from_ffi, style_font_from_ffi, text_decorations_from_ffi,
    theme_from_ffi,
};

mod editor_ui_abi;
pub use editor_ui_abi::*;

#[cfg(test)]
mod tests;
