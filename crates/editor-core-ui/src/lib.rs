//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

mod command_json;
mod editor_ui;
#[path = "lib/error.rs"]
mod error;
mod ime;
#[path = "lib/json_helpers.rs"]
mod json_helpers;
mod keybindings;
#[path = "lib/lsp_request_events/mod.rs"]
mod lsp_request_events;
#[path = "lib/lsp_result_events.rs"]
mod lsp_result_events;
#[path = "lib/lsp_shared/mod.rs"]
mod lsp_shared;
mod multi_document;
#[path = "lib/prelude.rs"]
mod prelude;
#[path = "lib/render_helpers.rs"]
mod render_helpers;
#[path = "lib/state/mod.rs"]
mod state;
#[path = "lib/state_events.rs"]
mod state_events;
#[path = "lib/theme.rs"]
mod theme;
#[path = "lib/treesitter_worker.rs"]
mod treesitter_worker;
mod windowing;

pub(crate) use json_helpers::*;
pub(crate) use lsp_request_events::*;
pub(crate) use lsp_result_events::*;
pub(crate) use lsp_shared::*;
pub(crate) use prelude::*;
pub(crate) use render_helpers::*;
pub(crate) use state::{
    EditorUiDoc, MarkedRange, MinimapCache, MouseDragState, MouseSelectionMode, RenderFrameCache,
    SearchQueryState,
};
pub(crate) use treesitter_worker::*;

pub use error::UiError;
pub use ime::{utf8_byte_offset_to_char_offset, utf8_byte_range_to_char_range};
pub use keybindings::{
    Key, KeyStroke, Keybinding, KeybindingContext, KeybindingResolver, KeybindingResolverResult,
    KeybindingWhen, Keymap, Modifiers, Platform, ResolvedCommand, dispatch_command_to_editor_ui,
};
pub use lsp_request_events::{EditorLspRequestEvent, EditorLspRequestEventsSnapshot};
pub use lsp_result_events::{EditorLspResultEvent, EditorLspResultEventsSnapshot};
pub use multi_document::{
    MultiDocumentEditorUi, MultiDocumentLspRequestEvent, MultiDocumentLspRequestEventsSnapshot,
    MultiDocumentLspResultEvent, MultiDocumentLspResultEventsSnapshot, MultiDocumentStateEvent,
    MultiDocumentStateEventsSnapshot, TabId, TabSearchResult, WorkspaceDiagnostic,
    WorkspaceDiagnosticDocumentReport, WorkspaceDiagnosticMarker,
    WorkspaceDiagnosticMarkersSnapshot, WorkspaceDiagnosticTarget, WorkspaceDiagnosticsEvent,
    WorkspaceDiagnosticsEventsSnapshot, WorkspaceDiagnosticsSnapshot, WorkspaceDiagnosticsStore,
};
pub use state::EditorUi;
pub use state_events::{
    EditorUiDirtyStateEvent, EditorUiLayoutStateEvent, EditorUiPositionStateEvent,
    EditorUiSelectionRangeStateEvent, EditorUiSelectionStateEvent, EditorUiStateEvent,
    EditorUiStateEventsSnapshot, EditorUiTextStateEvent, EditorUiViewportRangeStateEvent,
    EditorUiViewportStateEvent,
};
pub use theme::{ChromeTheme, DamageRect};
pub use windowing::{WindowingError, rgba8_to_argb_u32};

#[cfg(test)]
mod tests;
