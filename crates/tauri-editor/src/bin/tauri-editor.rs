use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use tauri::Manager;
use tauri_editor::{EditorBackend, EditorKey, KeyModifiers};
use tauri_plugin_clipboard_manager::ClipboardExt;

#[derive(Debug)]
struct AppState {
    backend: Mutex<EditorBackend>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct FrameSnapshot {
    snapshot: tauri_editor::snapshot::ViewportSnapshot,
    cursor: (u32, u32),
    selection: Option<((u32, u32), (u32, u32))>,
}

#[tauri::command]
fn set_viewport(
    state: tauri::State<'_, AppState>,
    width_cells: u32,
    height_rows: u32,
) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend
        .set_viewport_width(width_cells as usize)
        .map_err(|e| e.to_string())?;
    backend
        .set_viewport_height(height_rows as usize)
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn get_viewport(
    state: tauri::State<'_, AppState>,
    start_row: u32,
    count: u32,
) -> Result<tauri_editor::snapshot::ViewportSnapshot, String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend
        .viewport_snapshot(start_row as usize, count as usize)
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn get_frame(
    state: tauri::State<'_, AppState>,
    start_row: u32,
    count: u32,
) -> Result<FrameSnapshot, String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    let snapshot = backend
        .viewport_snapshot(start_row as usize, count as usize)
        .map_err(|e| e.to_string())?;
    let cursor = backend.cursor_overlay().map_err(|e| e.to_string())?;
    let selection = backend.selection_overlay().map_err(|e| e.to_string())?;
    Ok(FrameSnapshot {
        snapshot,
        cursor,
        selection,
    })
}

#[tauri::command]
fn get_cursor(state: tauri::State<'_, AppState>) -> Result<(u32, u32), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.cursor_overlay().map_err(|e| e.to_string())
}

#[tauri::command]
fn get_selection(
    state: tauri::State<'_, AppState>,
) -> Result<Option<((u32, u32), (u32, u32))>, String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.selection_overlay().map_err(|e| e.to_string())
}

#[tauri::command]
fn key_down(
    state: tauri::State<'_, AppState>,
    key: EditorKey,
    modifiers: KeyModifiers,
) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend
        .handle_key_down(key, modifiers)
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn mouse_down(
    state: tauri::State<'_, AppState>,
    row: u32,
    x_cells: u32,
    modifiers: KeyModifiers,
) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend
        .move_cursor_to_composed_row(row as usize, x_cells as usize, modifiers.shift)
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn insert_text(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.insert_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn composition_start(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.composition_start().map_err(|e| e.to_string())
}

#[tauri::command]
fn composition_update(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.composition_update(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn composition_end(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.composition_end(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn insert_newline(state: tauri::State<'_, AppState>, auto_indent: bool) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend
        .insert_newline(auto_indent)
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn insert_tab(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.insert_tab().map_err(|e| e.to_string())
}

#[tauri::command]
fn backspace(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.backspace().map_err(|e| e.to_string())
}

#[tauri::command]
fn delete_forward(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.delete_forward().map_err(|e| e.to_string())
}

#[tauri::command]
fn undo(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.undo().map_err(|e| e.to_string())
}

#[tauri::command]
fn redo(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.redo().map_err(|e| e.to_string())
}

#[tauri::command]
fn select_all(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.select_all().map_err(|e| e.to_string())
}

#[tauri::command]
fn copy(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    let text = backend.selection_text().map_err(|e| e.to_string())?;
    app.clipboard().write_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn cut(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    let text = backend.cut_selection_text().map_err(|e| e.to_string())?;
    app.clipboard().write_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn paste(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    let text = app.clipboard().read_text().map_err(|e| e.to_string())?;
    backend.insert_text(text).map_err(|e| e.to_string())
}

fn main() {
    let file_path = std::env::args_os().nth(1).map(PathBuf::from);

    let backend = match file_path.as_deref() {
        Some(path) => EditorBackend::open_file(path, 80).unwrap_or_else(|err| {
            eprintln!("failed to open file: {err}");
            EditorBackend::open_text(None, "", 80).expect("open empty text must succeed")
        }),
        None => EditorBackend::open_text(None, "", 80).expect("open empty text must succeed"),
    };

    tauri::Builder::default()
        .manage(AppState {
            backend: Mutex::new(backend),
        })
        .invoke_handler(tauri::generate_handler![
            set_viewport,
            get_viewport,
            get_frame,
            get_cursor,
            get_selection,
            key_down,
            mouse_down,
            insert_text,
            composition_start,
            composition_update,
            composition_end,
            insert_newline,
            insert_tab,
            backspace,
            delete_forward,
            undo,
            redo,
            select_all,
            copy,
            cut,
            paste
        ])
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                window.set_title("tauri-editor").ok();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
