use super::*;

thread_local! {
    pub(crate) static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
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

pub(crate) fn ffi_catch<T, F>(f: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => Err("panic across FFI boundary".to_string()),
    }
}

pub(crate) fn make_c_string_ptr(mut s: String) -> *mut c_char {
    if s.contains('\0') {
        // CString forbids interior NUL. Keep JSON parseable and deterministic.
        s = s.replace('\0', "\\u0000");
    }
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("").expect("empty cstring").into_raw(),
    }
}

pub(crate) fn json_ptr(value: Value) -> *mut c_char {
    make_c_string_ptr(value.to_string())
}

pub(crate) fn result_json_ptr<T, F>(default: *mut c_char, f: F) -> *mut c_char
where
    F: FnOnce() -> Result<T, String>,
    T: Into<Value>,
{
    match ffi_catch(f) {
        Ok(v) => {
            clear_last_error();
            json_ptr(v.into())
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

pub(crate) fn result_ptr<T, F>(default: *mut T, f: F) -> *mut T
where
    F: FnOnce() -> Result<*mut T, String>,
{
    match ffi_catch(f) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

pub(crate) fn result_bool<F>(default: bool, f: F) -> bool
where
    F: FnOnce() -> Result<bool, String>,
{
    match ffi_catch(f) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

pub(crate) fn require_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller promises unique mutable pointer.
    Ok(unsafe { &mut *ptr })
}

pub(crate) fn require_ref<'a, T>(ptr: *const T, name: &str) -> Result<&'a T, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller promises valid pointer.
    Ok(unsafe { &*ptr })
}

pub(crate) fn require_string(ptr: *const c_char, name: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller provides NUL-terminated string.
    let cstr = unsafe { CStr::from_ptr(ptr) };
    cstr.to_str()
        .map(|s| s.to_string())
        .map_err(|err| format!("{name} is not valid UTF-8: {err}"))
}

pub(crate) fn optional_string(ptr: *const c_char, name: &str) -> Result<Option<String>, String> {
    if ptr.is_null() {
        return Ok(None);
    }
    require_string(ptr, name).map(Some)
}

pub(crate) fn parse_json<T: for<'de> Deserialize<'de>>(
    text: &str,
    what: &str,
) -> Result<T, String> {
    serde_json::from_str(text).map_err(|err| format!("invalid {what} JSON: {err}"))
}

pub(crate) fn parse_json_value(text: &str, what: &str) -> Result<Value, String> {
    serde_json::from_str(text).map_err(|err| format!("invalid {what} JSON: {err}"))
}

pub(crate) fn status_result<F>(f: F) -> i32
where
    F: FnOnce() -> Result<(), (EcfStatus, String)>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(())) => {
            clear_last_error();
            EcfStatus::Ok.code()
        }
        Ok(Err((status, msg))) => {
            set_last_error(msg);
            status.code()
        }
        Err(_) => {
            set_last_error("panic across FFI boundary");
            EcfStatus::Internal.code()
        }
    }
}

pub(crate) fn checked_u32(v: usize, what: &str) -> Result<u32, (EcfStatus, String)> {
    u32::try_from(v).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{what} exceeds u32 range: {v}"),
        )
    })
}

pub(crate) fn checked_u16(v: usize, what: &str) -> Result<u16, (EcfStatus, String)> {
    u16::try_from(v).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{what} exceeds u16 range: {v}"),
        )
    })
}

pub(crate) fn usize_from_u32(v: u32, what: &str) -> Result<usize, String> {
    usize::try_from(v).map_err(|_| format!("{what} exceeds usize range: {v}"))
}

pub(crate) fn usize_from_u64(v: u64, what: &str) -> Result<usize, String> {
    usize::try_from(v).map_err(|_| format!("{what} exceeds usize range: {v}"))
}

pub(crate) fn u64_from_usize(v: usize, what: &str) -> Result<u64, String> {
    u64::try_from(v).map_err(|_| format!("{what} exceeds u64 range: {v}"))
}

pub(crate) fn status_usize_from_u32(v: u32, what: &str) -> Result<usize, (EcfStatus, String)> {
    usize_from_u32(v, what).map_err(|msg| (EcfStatus::InvalidArgument, msg))
}

pub(crate) fn require_utf8_bytes<'a>(
    ptr: *const u8,
    len: u32,
    name: &str,
) -> Result<&'a str, (EcfStatus, String)> {
    if len == 0 {
        return Ok("");
    }
    if ptr.is_null() {
        return Err((
            EcfStatus::InvalidArgument,
            format!("{name} is null but len={len}"),
        ));
    }
    let len_usize = usize::try_from(len).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{name} length exceeds usize: {len}"),
        )
    })?;
    // SAFETY: pointer checked for non-null and len provided by caller.
    let bytes = unsafe { slice::from_raw_parts(ptr, len_usize) };
    std::str::from_utf8(bytes).map_err(|err| (EcfStatus::InvalidUtf8, format!("{name}: {err}")))
}
