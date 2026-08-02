use super::*;
use editor_core::SearchOptions;
use serde_json::json;

/// Search all open tabs and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let results = multi
            .search_all_tabs(query, options)
            .map_err(|err| format!("search failed: {err}"))?;
        let value = json!({
            "results": results
                .iter()
                .map(|result| json!({
                    "tab_id": result.tab_id.get(),
                    "matches": result
                        .matches
                        .iter()
                        .map(|m| json!({ "start": m.start, "end": m.end }))
                        .collect::<Vec<_>>(),
                }))
                .collect::<Vec<_>>(),
        });
        Ok(value.to_string())
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}
