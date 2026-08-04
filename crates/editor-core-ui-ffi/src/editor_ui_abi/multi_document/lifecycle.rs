use super::*;

/// Create a new multi-document UI orchestrator handle.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_new() -> *mut MultiDocumentEditorUi {
    match ffi_catch(|| Ok(Box::into_raw(Box::new(MultiDocumentEditorUi::new())))) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Free a multi-document UI orchestrator handle.
///
/// # Safety
///
/// `multi` must be a valid pointer returned by `editor_core_ui_ffi_multi_document_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_free(multi: *mut MultiDocumentEditorUi) {
    if multi.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(multi));
    }
}
