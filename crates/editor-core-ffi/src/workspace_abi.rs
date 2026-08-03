use super::*;

/// Create a new workspace.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_new() -> *mut EcfWorkspace {
    result_ptr(ptr::null_mut(), || {
        Ok(Box::into_raw(Box::new(EcfWorkspace {
            inner: Workspace::new(),
        })))
    })
}

/// Destroy a workspace handle.
///
/// # Safety
///
/// `workspace` must be a valid pointer returned by `editor_core_ffi_workspace_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_free(workspace: *mut EcfWorkspace) {
    if workspace.is_null() {
        return;
    }
    // SAFETY: pointer must come from editor_core_ffi_workspace_new.
    unsafe {
        drop(Box::from_raw(workspace));
    }
}

/// Open a buffer and create its initial view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_open_buffer(
    workspace: *mut EcfWorkspace,
    uri: *const c_char,
    text: *const c_char,
    viewport_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let uri = optional_string(uri, "uri")?;
        let text = require_string(text, "text")?;
        let viewport_width = usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let opened = workspace
            .inner
            .open_buffer(uri, &text, viewport_width)
            .map_err(|err| format!("open_buffer failed: {err:?}"))?;
        Ok(value_open_buffer_result(opened))
    })
}

/// Typed ABI variant: open a buffer and create its initial view.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `text` must be a valid NUL-terminated UTF-8 string pointer.
/// - `out_result` must be a valid writable pointer to an `EcfOpenBufferResult`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_open_buffer_typed(
    workspace: *mut EcfWorkspace,
    uri: *const c_char,
    text: *const c_char,
    viewport_width: u32,
    out_result: *mut EcfOpenBufferResult,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_result.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_result is null".to_string()));
        }
        let uri =
            optional_string(uri, "uri").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_string(text, "text")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let viewport_width = status_usize_from_u32(viewport_width, "viewport_width")?.max(1);

        let opened = workspace
            .inner
            .open_buffer(uri, &text, viewport_width)
            .map_err(|err| (EcfStatus::Internal, format!("open_buffer failed: {err:?}")))?;

        let result = EcfOpenBufferResult {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfOpenBufferResult>() as u32,
            buffer_id: opened.buffer_id.get(),
            view_id: opened.view_id.get(),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_result = result;
        }
        Ok(())
    })
}

/// Close a buffer by id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_close_buffer(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .close_buffer(BufferId::from_raw(buffer_id))
            .map_err(|err| format!("close_buffer failed: {err:?}"))?;
        Ok(true)
    })
}

/// Close a view by id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_close_view(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .close_view(ViewId::from_raw(view_id))
            .map_err(|err| format!("close_view failed: {err:?}"))?;
        Ok(true)
    })
}

/// Create a new view for an existing buffer.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_create_view(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    viewport_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let viewport_width = usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let view_id = workspace
            .inner
            .create_view(BufferId::from_raw(buffer_id), viewport_width)
            .map_err(|err| format!("create_view failed: {err:?}"))?;
        Ok(json!({ "view_id": view_id.get() }))
    })
}

/// Typed ABI variant: create a new view for an existing buffer.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_result` must be a valid writable pointer to an `EcfCreateViewResult`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_create_view_typed(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    viewport_width: u32,
    out_result: *mut EcfCreateViewResult,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_result.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_result is null".to_string()));
        }

        let viewport_width = status_usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let view_id = workspace
            .inner
            .create_view(BufferId::from_raw(buffer_id), viewport_width)
            .map_err(|err| (EcfStatus::Internal, format!("create_view failed: {err:?}")))?;

        let result = EcfCreateViewResult {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfCreateViewResult>() as u32,
            view_id: view_id.get(),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_result = result;
        }
        Ok(())
    })
}

/// Set active view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_active_view(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .set_active_view(ViewId::from_raw(view_id))
            .map_err(|err| format!("set_active_view failed: {err:?}"))?;
        Ok(true)
    })
}

/// Return workspace basic stats and active ids as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_info_json(
    workspace: *const EcfWorkspace,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        workspace_info_value(workspace).map_err(|(_, message)| message)
    })
}

/// Return workspace basic stats and active ids as a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_info_envelope_json(
    workspace: *const EcfWorkspace,
) -> *mut c_char {
    workspace_result_envelope_json_ptr("info", || workspace_info_value(workspace))
}

fn workspace_info_value(workspace: *const EcfWorkspace) -> Result<Value, (EcfStatus, String)> {
    let workspace = require_ref(workspace, "workspace")
        .map_err(|message| (EcfStatus::InvalidArgument, message))?;
    Ok(json!({
        "buffer_count": workspace.inner.len(),
        "view_count": workspace.inner.view_count(),
        "is_empty": workspace.inner.is_empty(),
        "active_view_id": workspace.inner.active_view_id().map(|id| id.get()),
        "active_buffer_id": workspace.inner.active_buffer_id().map(|id| id.get()),
    }))
}

fn workspace_error_status(err: &WorkspaceError) -> EcfStatus {
    match err {
        WorkspaceError::BufferNotFound(_) | WorkspaceError::ViewNotFound(_) => EcfStatus::NotFound,
        WorkspaceError::UriAlreadyOpen(_) => EcfStatus::InvalidArgument,
        WorkspaceError::CommandFailed { .. } => EcfStatus::CommandFailed,
        WorkspaceError::ApplyEditsFailed { .. } => EcfStatus::Internal,
    }
}

fn workspace_error_result(err: WorkspaceError, prefix: &str) -> (EcfStatus, String) {
    let status = workspace_error_status(&err);
    (status, format!("{prefix} failed: {err:?}"))
}

/// Typed ABI variant: return workspace basic stats and active ids.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_info` must be a valid writable pointer to an `EcfWorkspaceInfo`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_get_info(
    workspace: *const EcfWorkspace,
    out_info: *mut EcfWorkspaceInfo,
) -> i32 {
    status_result(|| {
        let workspace = require_ref(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_info.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_info is null".to_string()));
        }

        let active_view_id = workspace.inner.active_view_id().map(|id| id.get());
        let active_buffer_id = workspace.inner.active_buffer_id().map(|id| id.get());

        let info = EcfWorkspaceInfo {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfWorkspaceInfo>() as u32,
            buffer_count: workspace.inner.len() as u64,
            view_count: workspace.inner.view_count() as u64,
            is_empty: if workspace.inner.is_empty() { 1 } else { 0 },
            has_active_view_id: if active_view_id.is_some() { 1 } else { 0 },
            has_active_buffer_id: if active_buffer_id.is_some() { 1 } else { 0 },
            reserved0: 0,
            active_view_id: active_view_id.unwrap_or(0),
            active_buffer_id: active_buffer_id.unwrap_or(0),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_info = info;
        }

        Ok(())
    })
}

/// Execute one command against a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_execute_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    command_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let command_json = require_string(command_json, "command_json")?;
        let command = parse_command_from_json(&command_json)?;
        let result = workspace
            .inner
            .execute(ViewId::from_raw(view_id), command)
            .map_err(|err| format!("workspace execute failed: {err:?}"))?;
        Ok(value_command_result(result))
    })
}

/// Execute one command against a view and return a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_execute_envelope_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    command_json: *const c_char,
) -> *mut c_char {
    result_envelope_json_ptr(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|message| (EcfStatus::InvalidArgument, message))?;
        let command_json = require_string_status(command_json, "command_json")?;
        let command = parse_command_from_json(&command_json)
            .map_err(|message| (EcfStatus::Parse, message))?;
        let result = workspace
            .inner
            .execute(ViewId::from_raw(view_id), command)
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace execute failed: {err:?}"),
                )
            })?;
        Ok(value_command_result(result))
    })
}

/// Apply one or more processing edits to a workspace buffer.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_apply_processing_edits_json(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    edits_json: *const c_char,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let edits_json = require_string(edits_json, "edits_json")?;
        let edits = parse_processing_edits(&edits_json)?;
        workspace
            .inner
            .apply_processing_edits(BufferId::from_raw(buffer_id), edits)
            .map_err(|err| format!("apply_processing_edits failed: {err:?}"))?;
        Ok(true)
    })
}

/// Get buffer text as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_buffer_text_json(
    workspace: *const EcfWorkspace,
    buffer_id: u64,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        workspace_buffer_text_value(workspace, buffer_id).map_err(|(_, message)| message)
    })
}

/// Get buffer text as a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_buffer_text_envelope_json(
    workspace: *const EcfWorkspace,
    buffer_id: u64,
) -> *mut c_char {
    workspace_result_envelope_json_ptr("buffer_text", || {
        workspace_buffer_text_value(workspace, buffer_id)
    })
}

fn workspace_buffer_text_value(
    workspace: *const EcfWorkspace,
    buffer_id: u64,
) -> Result<Value, (EcfStatus, String)> {
    let workspace = require_ref(workspace, "workspace")
        .map_err(|message| (EcfStatus::InvalidArgument, message))?;
    let text = workspace
        .inner
        .buffer_text(BufferId::from_raw(buffer_id))
        .map_err(|err| workspace_error_result(err, "buffer_text"))?;
    Ok(json!({ "text": text }))
}

/// Get viewport state for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_state_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        workspace_viewport_state_value(workspace, view_id).map_err(|(_, message)| message)
    })
}

/// Get viewport state for a view as a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_state_envelope_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> *mut c_char {
    workspace_result_envelope_json_ptr("viewport_state", || {
        workspace_viewport_state_value(workspace, view_id)
    })
}

fn workspace_viewport_state_value(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> Result<Value, (EcfStatus, String)> {
    let workspace = require_mut(workspace, "workspace")
        .map_err(|message| (EcfStatus::InvalidArgument, message))?;
    let state = workspace
        .inner
        .viewport_state_for_view(ViewId::from_raw(view_id))
        .map_err(|err| workspace_error_result(err, "viewport_state_for_view"))?;
    Ok(value_workspace_viewport_state(&state))
}

/// Typed ABI variant: return workspace viewport state for a view.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_state` must be a valid writable pointer to an `EcfWorkspaceViewportState`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_get_viewport_state(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    out_state: *mut EcfWorkspaceViewportState,
) -> i32 {
    fn saturating_u32(value: usize) -> u32 {
        value.try_into().unwrap_or(u32::MAX)
    }

    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_state.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_state is null".to_string()));
        }

        let state = workspace
            .inner
            .viewport_state_for_view(ViewId::from_raw(view_id))
            .map_err(|err| {
                (
                    EcfStatus::Internal,
                    format!("viewport_state_for_view failed: {err:?}"),
                )
            })?;

        let height_rows = state.height.map(saturating_u32).unwrap_or(0);
        let has_height = if state.height.is_some() { 1 } else { 0 };

        let out = EcfWorkspaceViewportState {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfWorkspaceViewportState>() as u32,
            width_cells: saturating_u32(state.width),
            height_rows,
            has_height,
            scroll_top: saturating_u32(state.scroll_top),
            sub_row_offset: state.smooth_scroll.sub_row_offset as u32,
            overscan_rows: saturating_u32(state.smooth_scroll.overscan_rows),
            visible_start: saturating_u32(state.visible_lines.start),
            visible_end: saturating_u32(state.visible_lines.end),
            prefetch_start: saturating_u32(state.prefetch_lines.start),
            prefetch_end: saturating_u32(state.prefetch_lines.end),
            total_visual_lines: saturating_u32(state.total_visual_lines),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_state = out;
        }
        Ok(())
    })
}

/// Set viewport height for a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_viewport_height(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    height: u32,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let height = usize_from_u32(height, "height")?;
        workspace
            .inner
            .set_viewport_height(ViewId::from_raw(view_id), height)
            .map_err(|err| format!("set_viewport_height failed: {err:?}"))?;
        Ok(true)
    })
}

/// Set smooth-scroll state for a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_smooth_scroll_state(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    top_visual_row: u32,
    sub_row_offset: u16,
    overscan_rows: u32,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let top_visual_row = usize_from_u32(top_visual_row, "top_visual_row")?;
        let overscan_rows = usize_from_u32(overscan_rows, "overscan_rows")?;
        workspace
            .inner
            .set_smooth_scroll_state(
                ViewId::from_raw(view_id),
                ViewSmoothScrollState {
                    top_visual_row,
                    sub_row_offset,
                    overscan_rows,
                },
            )
            .map_err(|err| format!("set_smooth_scroll_state failed: {err:?}"))?;
        Ok(true)
    })
}

/// Get styled viewport snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_styled_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_viewport_content_styled(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_viewport_content_styled failed: {err:?}"))?;
        Ok(value_headless_grid(&grid))
    })
}

/// Get styled viewport snapshot for a view as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_styled_envelope_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "workspace_viewport_styled",
        Some(view_id),
        start_visual_row,
        count,
        || {
            let workspace = require_mut(workspace, "workspace")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = workspace
                .inner
                .get_viewport_content_styled(ViewId::from_raw(view_id), start_visual_row, count)
                .map_err(|err| {
                    (
                        EcfStatus::Internal,
                        format!("get_viewport_content_styled failed: {err:?}"),
                    )
                })?;
            Ok(value_headless_grid(&grid))
        },
    )
}

/// Get minimap snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_minimap_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_minimap_content(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_minimap_content failed: {err:?}"))?;
        Ok(value_minimap_grid(&grid))
    })
}

/// Get minimap snapshot for a view as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_minimap_envelope_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "workspace_minimap",
        Some(view_id),
        start_visual_row,
        count,
        || {
            let workspace = require_mut(workspace, "workspace")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = workspace
                .inner
                .get_minimap_content(ViewId::from_raw(view_id), start_visual_row, count)
                .map_err(|err| {
                    (
                        EcfStatus::Internal,
                        format!("get_minimap_content failed: {err:?}"),
                    )
                })?;
            Ok(value_minimap_grid(&grid))
        },
    )
}

/// Get composed viewport snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_composed_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_viewport_content_composed(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_viewport_content_composed failed: {err:?}"))?;
        Ok(value_composed_grid(&grid))
    })
}

/// Get composed viewport snapshot for a view as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_composed_envelope_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "workspace_viewport_composed",
        Some(view_id),
        start_visual_row,
        count,
        || {
            let workspace = require_mut(workspace, "workspace")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = workspace
                .inner
                .get_viewport_content_composed(ViewId::from_raw(view_id), start_visual_row, count)
                .map_err(|err| {
                    (
                        EcfStatus::Internal,
                        format!("get_viewport_content_composed failed: {err:?}"),
                    )
                })?;
            Ok(value_composed_grid(&grid))
        },
    )
}

/// Search all open buffers.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_search_all_open_buffers_json(
    workspace: *const EcfWorkspace,
    query: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        workspace_search_all_open_buffers_value(workspace, query, options_json)
            .map_err(|(_, message)| message)
    })
}

/// Apply text edits grouped by buffer id.
///
/// Input JSON format:
/// `[ { "buffer_id": 1, "edits": [ {"start": 0, "end": 3, "text": "x"} ] } ]`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_apply_text_edits_json(
    workspace: *mut EcfWorkspace,
    edits_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        workspace_apply_text_edits_value(workspace, edits_json).map_err(|(_, message)| message)
    })
}

/// Search all open buffers and return a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_search_all_open_buffers_envelope_json(
    workspace: *const EcfWorkspace,
    query: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    workspace_result_envelope_json_ptr("search_all_open_buffers", || {
        workspace_search_all_open_buffers_value(workspace, query, options_json)
    })
}

/// Apply workspace text edits and return a stable result envelope.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_apply_text_edits_envelope_json(
    workspace: *mut EcfWorkspace,
    edits_json: *const c_char,
) -> *mut c_char {
    workspace_result_envelope_json_ptr("apply_text_edits", || {
        workspace_apply_text_edits_value(workspace, edits_json)
    })
}

#[derive(Debug, Deserialize)]
struct WorkspaceEditsItem {
    buffer_id: u64,
    edits: Vec<FfiTextEditSpec>,
}

fn workspace_search_all_open_buffers_value(
    workspace: *const EcfWorkspace,
    query: *const c_char,
    options_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let workspace = require_ref(workspace, "workspace")
        .map_err(|message| (EcfStatus::InvalidArgument, message))?;
    let query = require_string_status(query, "query")?;
    let options = if options_json.is_null() {
        SearchOptions::default()
    } else {
        let options_text = require_string_status(options_json, "options_json")?;
        let parsed: FfiSearchOptions = parse_json(&options_text, "search options")
            .map_err(|message| (EcfStatus::Parse, message))?;
        parsed.into()
    };

    let results = workspace
        .inner
        .search_all_open_buffers(&query, options)
        .map_err(|err| (EcfStatus::Internal, format!("search failed: {err}")))?;
    Ok(json!({
        "results": results
            .iter()
            .map(value_workspace_search_result)
            .collect::<Vec<_>>()
    }))
}

fn workspace_apply_text_edits_value(
    workspace: *mut EcfWorkspace,
    edits_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let workspace = require_mut(workspace, "workspace")
        .map_err(|message| (EcfStatus::InvalidArgument, message))?;
    let edits_json = require_string_status(edits_json, "edits_json")?;
    let parsed: Vec<WorkspaceEditsItem> = parse_json(&edits_json, "workspace text edits")
        .map_err(|message| (EcfStatus::Parse, message))?;

    let edits = parsed.into_iter().map(|item| {
        (
            BufferId::from_raw(item.buffer_id),
            item.edits
                .into_iter()
                .map(Into::into)
                .collect::<Vec<TextEditSpec>>(),
        )
    });

    let applied = workspace.inner.apply_text_edits(edits).map_err(|err| {
        (
            EcfStatus::Internal,
            format!("apply_text_edits failed: {err:?}"),
        )
    })?;

    Ok(json!({
        "applied": applied
            .into_iter()
            .map(|(id, count)| json!({ "buffer_id": id.get(), "edit_count": count }))
            .collect::<Vec<_>>()
    }))
}

fn workspace_result_envelope_json_ptr<F>(operation: &'static str, f: F) -> *mut c_char
where
    F: FnOnce() -> Result<Value, (EcfStatus, String)>,
{
    let envelope = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(value)) => {
            clear_last_error();
            workspace_result_envelope_success(operation, value)
        }
        Ok(Err((status, message))) => {
            set_last_error(message.clone());
            workspace_result_envelope_error(operation, status, message)
        }
        Err(_) => {
            let message = "panic across FFI boundary".to_string();
            set_last_error(message.clone());
            workspace_result_envelope_error(operation, EcfStatus::Internal, message)
        }
    };
    json_ptr(envelope)
}

fn workspace_result_envelope_success(operation: &'static str, value: Value) -> Value {
    json!({
        "ok": true,
        "status": "success",
        "operation": operation,
        "value": value,
        "error": Value::Null,
        "version": ECF_ABI_VERSION,
    })
}

fn workspace_result_envelope_error(
    operation: &'static str,
    status: EcfStatus,
    message: String,
) -> Value {
    json!({
        "ok": false,
        "status": "error",
        "operation": operation,
        "value": Value::Null,
        "error": {
            "code": ecf_status_label(status),
            "status": status.code(),
            "message": message,
        },
        "version": ECF_ABI_VERSION,
    })
}
