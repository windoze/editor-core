use editor_core_ui::UiError;
use libc::{c_char, c_int};
use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::mem;
use std::slice;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

pub(crate) fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = Some(msg.into());
    });
}

pub(crate) fn clear_last_error() {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = None;
    });
}

const INVALID_ARGUMENT_PREFIX: &str = "invalid argument: ";

pub(crate) fn invalid_argument(msg: impl Into<String>) -> String {
    format!("{INVALID_ARGUMENT_PREFIX}{}", msg.into())
}

fn strip_invalid_argument_prefix(err: &str) -> Option<&str> {
    err.strip_prefix(INVALID_ARGUMENT_PREFIX)
}

pub(crate) fn set_last_error_from_error(err: String) {
    let (_, msg) = classify_error(err);
    set_last_error(msg);
}

pub(crate) fn ffi_catch<T, F>(f: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => Err("panic across FFI boundary".to_string()),
    }
}

/// Run a `void`-returning FFI operation under `catch_unwind`, updating the thread-local last-error
/// slot. On success the error is cleared; on error (including a caught panic) the message is
/// recorded. This prevents a panic from unwinding across the `extern "C"` boundary.
pub(crate) fn ffi_void<F>(f: F)
where
    F: FnOnce() -> Result<(), String>,
{
    match ffi_catch(f) {
        Ok(()) => clear_last_error(),
        Err(err) => set_last_error_from_error(err),
    }
}

pub(crate) fn make_c_string_ptr(mut s: String) -> *mut c_char {
    if s.contains('\0') {
        // CString forbids interior NUL. Keep it deterministic.
        s = s.replace('\0', "\\u0000");
    }
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("").expect("empty cstring").into_raw(),
    }
}

pub(crate) fn require_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    // SAFETY: checked for null; caller promises valid pointer.
    Ok(unsafe { &mut *ptr })
}

pub(crate) fn require_out_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    // SAFETY: checked for null; caller promises valid output pointer.
    Ok(unsafe { &mut *ptr })
}

pub(crate) fn require_cstr<'a>(ptr: *const c_char, name: &str) -> Result<&'a CStr, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    Ok(unsafe { CStr::from_ptr(ptr) })
}

pub(crate) fn require_str<'a>(ptr: *const c_char, name: &str) -> Result<&'a str, String> {
    let cstr = require_cstr(ptr, name)?;
    cstr.to_str()
        .map_err(|_| invalid_argument(format!("{name} is not valid UTF-8")))
}

pub(crate) fn u32_to_usize(value: u32, name: &str) -> Result<usize, String> {
    usize::try_from(value).map_err(|_| {
        invalid_argument(format!(
            "{name} value {value} does not fit in usize on this platform"
        ))
    })
}

pub(crate) fn usize_to_u32(value: usize, name: &str) -> Result<u32, String> {
    u32::try_from(value)
        .map_err(|_| invalid_argument(format!("{name} value {value} exceeds the u32 ABI limit")))
}

fn ffi_count_to_usize<T>(value: u32, name: &str) -> Result<usize, String> {
    let len = u32_to_usize(value, name)?;
    let elem_size = mem::size_of::<T>().max(1);
    let max_len = isize::MAX as usize / elem_size;
    if len > max_len {
        return Err(invalid_argument(format!(
            "{name} value {value} exceeds the maximum slice length"
        )));
    }
    Ok(len)
}

pub(crate) unsafe fn ffi_slice_from_raw_parts<'a, T>(
    ptr: *const T,
    count: u32,
    ptr_name: &str,
    count_name: &str,
) -> Result<&'a [T], String> {
    let len = ffi_count_to_usize::<T>(count, count_name)?;
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(invalid_argument(format!("{ptr_name} is null")));
    }
    // SAFETY: caller promises `ptr` is valid for `len` elements; this helper validates null,
    // fixed-width conversion, and Rust slice length limits before constructing the slice.
    Ok(unsafe { slice::from_raw_parts(ptr, len) })
}

pub(crate) unsafe fn ffi_slice_from_raw_parts_mut<'a, T>(
    ptr: *mut T,
    count: u32,
    ptr_name: &str,
    count_name: &str,
) -> Result<&'a mut [T], String> {
    let len = ffi_count_to_usize::<T>(count, count_name)?;
    if len == 0 {
        return Ok(&mut []);
    }
    if ptr.is_null() {
        return Err(invalid_argument(format!("{ptr_name} is null")));
    }
    // SAFETY: caller promises `ptr` is valid for `len` elements; this helper validates null,
    // fixed-width conversion, and Rust slice length limits before constructing the slice.
    Ok(unsafe { slice::from_raw_parts_mut(ptr, len) })
}

pub(crate) fn status_from_error(err: String) -> c_int {
    let (status, msg) = classify_error(err);
    set_last_error(msg);
    status
}

pub(crate) fn classify_error(err: String) -> (c_int, String) {
    if let Some(msg) = strip_invalid_argument_prefix(&err) {
        (ECU_ERR_INVALID_ARGUMENT, msg.to_string())
    } else {
        (ECU_ERR_INTERNAL, err)
    }
}

pub(crate) const ECU_OK: c_int = 0;
pub(crate) const ECU_ERR_INVALID_ARGUMENT: c_int = 1;
pub(crate) const ECU_ERR_BUFFER_TOO_SMALL: c_int = 4;
pub(crate) const ECU_ERR_INTERNAL: c_int = 7;

pub(crate) fn status_code_name(status: c_int) -> &'static str {
    match status {
        ECU_ERR_INVALID_ARGUMENT => "invalid_argument",
        ECU_ERR_BUFFER_TOO_SMALL => "buffer_too_small",
        ECU_ERR_INTERNAL => "internal",
        _ => "unknown",
    }
}

pub(crate) fn status_from_invalid_argument(err: String) -> c_int {
    set_last_error(err);
    ECU_ERR_INVALID_ARGUMENT
}

pub(crate) fn map_ui_error(err: UiError) -> String {
    err.to_string()
}

/// Free a C string returned by this library.
///
/// # Safety
///
/// `ptr` must be a valid pointer returned by a function in this library that allocates C strings,
/// or null. The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

/// Retrieve the latest thread-local error message.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_last_error_message() -> *mut c_char {
    let message = LAST_ERROR.with(|slot| {
        slot.borrow()
            .clone()
            .unwrap_or_else(|| "no error".to_string())
    });
    make_c_string_ptr(message)
}
