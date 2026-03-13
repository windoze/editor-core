use std::path::PathBuf;
use std::sync::Mutex;

use tauri::Manager;
use tauri_editor::{EditorBackend, EditorKey, KeyModifiers};

#[derive(Debug)]
struct AppState {
    backend: Mutex<EditorBackend>,
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
fn get_cursor(state: tauri::State<'_, AppState>) -> Result<(u32, u32), String> {
    let mut backend = state.backend.lock().map_err(|_| "state lock poisoned")?;
    backend.cursor_overlay().map_err(|e| e.to_string())
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
            get_cursor,
            key_down
        ])
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                window.set_title("tauri-editor").ok();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
