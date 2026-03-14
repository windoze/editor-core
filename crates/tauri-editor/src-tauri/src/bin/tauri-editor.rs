use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use tauri::Manager;
use tauri_editor::{EditorBackend, EditorBackendError, EditorKey, KeyModifiers};
use tauri_plugin_clipboard_manager::ClipboardExt;

#[derive(Debug)]
struct AppState {
    backend: Mutex<EditorBackend>,
}

fn with_backend<T>(
    state: &tauri::State<'_, AppState>,
    f: impl FnOnce(&mut EditorBackend) -> Result<T, EditorBackendError>,
) -> Result<T, String> {
    let mut backend = match state.backend.lock() {
        Ok(guard) => guard,
        Err(poison) => {
            eprintln!("[tauri-editor] backend mutex poisoned; recovering");
            poison.into_inner()
        }
    };

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f(&mut backend)));
    match result {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(err)) => Err(err.to_string()),
        Err(_) => Err("tauri command panicked".to_string()),
    }
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
    with_backend(&state, |backend| {
        backend.set_viewport_width(width_cells as usize)?;
        backend.set_viewport_height(height_rows as usize)?;
        Ok(())
    })
}

#[tauri::command]
fn get_viewport(
    state: tauri::State<'_, AppState>,
    start_row: u32,
    count: u32,
) -> Result<tauri_editor::snapshot::ViewportSnapshot, String> {
    with_backend(&state, |backend| {
        backend.viewport_snapshot(start_row as usize, count as usize)
    })
}

#[tauri::command]
fn get_minimap(
    state: tauri::State<'_, AppState>,
    height: u32,
) -> Result<tauri_editor::snapshot::MinimapSnapshot, String> {
    let height = (height as usize).max(1);

    // minimap 计算可能较慢（尤其是大文件/软换行下 visual rows 很多），因此这里避免一次性持锁。
    // 我们先获取必要的元数据，然后按 chunk 多次锁/解锁去取局部 minimap grid，尽量减少对编辑/点击的阻塞。
    let (view_id, viewport_width_cells, doc_total_rows) = with_backend(&state, |backend| {
        let view_id = backend.view_id();
        let viewport_width_cells = backend
            .workspace_mut()
            .viewport_width_for_view(view_id)?
            .max(1);
        let doc_total_rows = backend
            .workspace_mut()
            .total_visual_lines_for_view(view_id)?;
        Ok((view_id, viewport_width_cells, doc_total_rows))
    })?;

    let total_rows_u32 = u32::try_from(doc_total_rows)
        .map_err(|_| format!("minimap total_rows 超出 u32 范围（total_rows={doc_total_rows}）"))?;

    let bucket_size = (doc_total_rows + height - 1) / height;
    let bucket_size = bucket_size.max(1);
    let bucket_size_u32 = u32::try_from(bucket_size)
        .map_err(|_| format!("minimap bucket_size 超出 u32 范围（bucket_size={bucket_size}）"))?;

    let mut samples: Vec<u8> = vec![0; height];
    if doc_total_rows == 0 {
        return Ok(tauri_editor::snapshot::MinimapSnapshot {
            total_rows: total_rows_u32,
            bucket_size: bucket_size_u32,
            samples,
        });
    }

    const CHUNK_ROWS: usize = 512;
    let mut start_row = 0usize;
    while start_row < doc_total_rows {
        let count = (doc_total_rows - start_row).min(CHUNK_ROWS);
        let grid = with_backend(&state, |backend| {
            backend
                .workspace_mut()
                .get_minimap_content(view_id, start_row, count)
                .map_err(EditorBackendError::from)
        })?;

        for (i, line) in grid.lines.iter().enumerate() {
            let row = start_row.saturating_add(i);
            let bucket = row / bucket_size;
            if bucket >= height {
                break;
            }
            let non_ws = line.non_whitespace_cells.min(viewport_width_cells);
            let v = ((non_ws * 255) / viewport_width_cells) as u8;
            samples[bucket] = samples[bucket].max(v);
        }

        start_row = start_row.saturating_add(count);
    }

    Ok(tauri_editor::snapshot::MinimapSnapshot {
        total_rows: total_rows_u32,
        bucket_size: bucket_size_u32,
        samples,
    })
}

#[tauri::command]
fn get_frame(
    state: tauri::State<'_, AppState>,
    start_row: u32,
    count: u32,
) -> Result<FrameSnapshot, String> {
    with_backend(&state, |backend| {
        let snapshot = backend.viewport_snapshot(start_row as usize, count as usize)?;
        let cursor = backend.cursor_overlay()?;
        let selection = backend.selection_overlay()?;
        Ok(FrameSnapshot {
            snapshot,
            cursor,
            selection,
        })
    })
}

#[tauri::command]
fn get_cursor(state: tauri::State<'_, AppState>) -> Result<(u32, u32), String> {
    with_backend(&state, |backend| backend.cursor_overlay())
}

#[tauri::command]
fn get_selection(
    state: tauri::State<'_, AppState>,
) -> Result<Option<((u32, u32), (u32, u32))>, String> {
    with_backend(&state, |backend| backend.selection_overlay())
}

#[tauri::command]
fn key_down(
    state: tauri::State<'_, AppState>,
    key: EditorKey,
    modifiers: KeyModifiers,
) -> Result<(), String> {
    with_backend(&state, |backend| backend.handle_key_down(key, modifiers))
}

#[tauri::command]
fn mouse_down(
    state: tauri::State<'_, AppState>,
    row: u32,
    x_cells: u32,
    modifiers: KeyModifiers,
) -> Result<(), String> {
    with_backend(&state, |backend| {
        backend.move_cursor_to_composed_row(row as usize, x_cells as usize, modifiers.shift)
    })
}

#[tauri::command]
fn mouse_drag(
    state: tauri::State<'_, AppState>,
    anchor_row: u32,
    anchor_x_cells: u32,
    row: u32,
    x_cells: u32,
) -> Result<(), String> {
    with_backend(&state, |backend| {
        backend.set_selection_by_composed_points(
            anchor_row as usize,
            anchor_x_cells as usize,
            row as usize,
            x_cells as usize,
        )
    })
}

#[tauri::command]
fn toggle_fold(
    state: tauri::State<'_, AppState>,
    start_line: u32,
    end_line: u32,
    collapsed: bool,
) -> Result<(), String> {
    with_backend(&state, |backend| {
        backend.toggle_fold(start_line as usize, end_line as usize, collapsed)
    })
}

#[tauri::command]
fn insert_text(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    with_backend(&state, |backend| backend.insert_text(text))
}

#[tauri::command]
fn composition_start(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.composition_start())
}

#[tauri::command]
fn composition_update(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    with_backend(&state, |backend| backend.composition_update(text))
}

#[tauri::command]
fn composition_end(state: tauri::State<'_, AppState>, text: String) -> Result<(), String> {
    with_backend(&state, |backend| backend.composition_end(text))
}

#[tauri::command]
fn insert_newline(state: tauri::State<'_, AppState>, auto_indent: bool) -> Result<(), String> {
    with_backend(&state, |backend| backend.insert_newline(auto_indent))
}

#[tauri::command]
fn insert_tab(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.insert_tab())
}

#[tauri::command]
fn backspace(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.backspace())
}

#[tauri::command]
fn delete_forward(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.delete_forward())
}

#[tauri::command]
fn undo(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.undo())
}

#[tauri::command]
fn redo(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.redo())
}

#[tauri::command]
fn select_all(state: tauri::State<'_, AppState>) -> Result<(), String> {
    with_backend(&state, |backend| backend.select_all())
}

#[tauri::command]
fn copy(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let text = with_backend(&state, |backend| backend.selection_text())?;
    app.clipboard().write_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn cut(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let text = with_backend(&state, |backend| backend.cut_selection_text())?;
    app.clipboard().write_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn paste(state: tauri::State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    let text = app.clipboard().read_text().map_err(|e| e.to_string())?;
    with_backend(&state, |backend| backend.insert_text(text))
}

#[tauri::command]
fn frontend_log(level: String, message: String) {
    eprintln!("[tauri-editor][frontend][{level}] {message}");
}

fn env_flag_enabled(name: &str) -> bool {
    let Some(v) = std::env::var_os(name) else {
        return false;
    };
    let s = v.to_string_lossy();
    let s = s.trim().to_ascii_lowercase();
    if s.is_empty() {
        return true;
    }
    !matches!(s.as_str(), "0" | "false" | "no" | "off")
}

#[tauri::command]
fn debug_hud_enabled() -> bool {
    cfg!(feature = "debug-hud") || env_flag_enabled("TAURI_EDITOR_DEBUG_HUD")
}

#[tauri::command]
fn open_devtools(window: tauri::WebviewWindow) -> Result<(), String> {
    #[cfg(debug_assertions)]
    {
        window.open_devtools();
        return Ok(());
    }
    #[cfg(not(debug_assertions))]
    {
        let _ = window;
        Err("devtools 未启用（需要 debug 构建）".to_string())
    }
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
            get_minimap,
            get_frame,
            get_cursor,
            get_selection,
            frontend_log,
            debug_hud_enabled,
            open_devtools,
            key_down,
            mouse_down,
            mouse_drag,
            toggle_fold,
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
                #[cfg(debug_assertions)]
                window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
