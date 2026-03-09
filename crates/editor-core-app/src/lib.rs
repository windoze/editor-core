//! `editor-core-app` — UI-agnostic “editor application shell” primitives.
//!
//! This crate is intentionally **not** a GUI framework. It provides shared logic and data models
//! that typical editor frontends need on top of the `editor-core` kernel:
//!
//! - workspace filesystem traversal (file index, explorer tree helpers)
//! - fuzzy matching (command palette / quick-open building block)
//! - session/recents persistence helpers (optional “hot exit” style snapshots)
//!
//! The goal is to implement as much as possible once in Rust and reuse across platforms.

mod command_palette;
mod file_explorer;
mod file_io;
mod find_in_files;
mod fuzzy;
mod observability;
mod pane_layout;
mod search_results;
mod session;
mod settings;
mod status_bar;
mod workspace_index;
mod workspace_io;

pub use command_palette::{CommandPalette, CommandPaletteItem, CommandPaletteResult};
pub use file_explorer::{
    FileExplorer, FileExplorerEntry, FileExplorerEntryKind, FileExplorerError,
};
pub use file_io::{FileIoError, FileIoOptions, read_utf8_file, write_utf8_file_atomic};
pub use find_in_files::{
    FindInFilesConfig, FindInFilesError, FindInFilesFileResult, FindInFilesLineMatch, find_in_files,
};
pub use fuzzy::FuzzyMatcher;
pub use observability::{AppLog, LogEntry, LogLevel};
pub use pane_layout::{PaneId, PaneLayout, SplitDirection, WindowId, WindowManager};
pub use search_results::{
    AnchoredMatchRange, BufferSearchResults, SearchResultsError, SearchResultsModel,
};
pub use session::{
    AppSession, AppSessionError, BufferSnapshot, HotExitSnapshot, ViewSnapshot, load_session_json,
    save_session_json,
};
pub use settings::{Settings, SettingsError, SettingsStore, apply_settings_to_view};
pub use status_bar::{StatusBarError, StatusBarInfo, status_bar_info};
pub use workspace_index::{FileIndexEntry, WorkspaceFileIndex, WorkspaceFileIndexError};
pub use workspace_io::{SaveAllResult, WorkspaceIo, WorkspaceIoError, open_file_into_workspace};
