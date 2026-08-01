use super::*;

/// Create a Sublime processor from YAML syntax text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_new_from_yaml(
    yaml: *const c_char,
) -> *mut EcfSublimeProcessor {
    result_ptr(ptr::null_mut(), || {
        let yaml = require_string(yaml, "yaml")?;
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_str(&yaml)
            .map_err(|err| format!("failed to load syntax from YAML: {err}"))?;
        let processor = SublimeProcessor::new(syntax, syntax_set);
        Ok(Box::into_raw(Box::new(EcfSublimeProcessor {
            inner: processor,
        })))
    })
}

/// Create a Sublime processor from syntax file path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_new_from_path(
    path: *const c_char,
) -> *mut EcfSublimeProcessor {
    result_ptr(ptr::null_mut(), || {
        let path = require_string(path, "path")?;
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_path(&path)
            .map_err(|err| format!("failed to load syntax from path: {err}"))?;
        let processor = SublimeProcessor::new(syntax, syntax_set);
        Ok(Box::into_raw(Box::new(EcfSublimeProcessor {
            inner: processor,
        })))
    })
}

/// Destroy a Sublime processor.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_sublime_processor_free(
    processor: *mut EcfSublimeProcessor,
) {
    if processor.is_null() {
        return;
    }
    // SAFETY: pointer must come from a constructor in this crate.
    unsafe {
        drop(Box::from_raw(processor));
    }
}

/// Add a search path used to resolve `Packages/...` references.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_add_search_path(
    processor: *mut EcfSublimeProcessor,
    path: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let path = require_string(path, "path")?;
        processor.inner.syntax_set_mut().add_search_path(path);
        Ok(true)
    })
}

/// Load syntax YAML into processor's syntax set.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate.
/// `yaml` must be a valid null-terminated UTF-8 C string pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_sublime_processor_load_syntax_from_yaml(
    processor: *mut EcfSublimeProcessor,
    yaml: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let yaml = require_string(yaml, "yaml")?;
        processor
            .inner
            .syntax_set_mut()
            .load_from_str(&yaml)
            .map_err(|err| format!("failed to load syntax from YAML: {err}"))?;
        Ok(true)
    })
}

/// Load syntax from path into processor's syntax set.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_load_syntax_from_path(
    processor: *mut EcfSublimeProcessor,
    path: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let path = require_string(path, "path")?;
        processor
            .inner
            .syntax_set_mut()
            .load_from_path(&path)
            .map_err(|err| format!("failed to load syntax from path: {err}"))?;
        Ok(true)
    })
}

/// Switch active syntax by Sublime reference.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_set_active_syntax_by_reference(
    processor: *mut EcfSublimeProcessor,
    reference: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let reference = require_string(reference, "reference")?;

        let preserve = processor.inner.preserve_collapsed_folds();
        let mut scope_mapper =
            std::mem::replace(&mut processor.inner.scope_mapper, SublimeScopeMapper::new());
        let mut syntax_set = std::mem::take(processor.inner.syntax_set_mut());
        let syntax = syntax_set
            .load_by_reference(&reference)
            .map_err(|err| format!("failed to load syntax by reference: {err}"))?;

        let mut next = SublimeProcessor::new(syntax, syntax_set);
        next.scope_mapper = std::mem::replace(&mut scope_mapper, SublimeScopeMapper::new());
        next.set_preserve_collapsed_folds(preserve);
        processor.inner = next;

        Ok(true)
    })
}

/// Configure whether fold replacement preserves collapsed state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_set_preserve_collapsed_folds(
    processor: *mut EcfSublimeProcessor,
    preserve: bool,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        processor.inner.set_preserve_collapsed_folds(preserve);
        Ok(true)
    })
}

/// Run Sublime processing and return generated processing edits JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_process_json(
    processor: *mut EcfSublimeProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_mut(processor, "processor")?;
        let state = require_ref(state, "state")?;
        let edits = processor
            .inner
            .process(&state.inner)
            .map_err(|err| format!("sublime process failed: {err}"))?;
        Ok(json!({
            "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
        }))
    })
}

/// Run Sublime processor and apply edits to state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_apply(
    processor: *mut EcfSublimeProcessor,
    state: *mut EcfEditorState,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let state = require_mut(state, "state")?;
        state
            .inner
            .apply_processor(&mut processor.inner)
            .map_err(|err| format!("sublime apply failed: {err}"))?;
        Ok(true)
    })
}

/// Return scope string for a style id in current Sublime scope mapper.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_scope_for_style_id(
    processor: *const EcfSublimeProcessor,
    style_id: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_ref(processor, "processor")?;
        Ok(json!({
            "scope": processor.inner.scope_mapper.scope_for_style_id(style_id)
        }))
    })
}

/// Tree-sitter language function pointer type expected by this FFI.
pub type EcfTreeSitterLanguageFn = unsafe extern "C" fn() -> *const ();

/// Create a Tree-sitter processor.
///
/// `capture_styles_json` is optional object JSON: `{ "capture.name": 123, ... }`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_new(
    language_fn: Option<EcfTreeSitterLanguageFn>,
    highlights_query: *const c_char,
    folds_query: *const c_char,
    capture_styles_json: *const c_char,
    style_layer: u32,
    preserve_collapsed_folds: bool,
) -> *mut EcfTreeSitterProcessor {
    result_ptr(ptr::null_mut(), || {
        let language_fn = language_fn.ok_or_else(|| "language_fn is null".to_string())?;
        let highlights_query = require_string(highlights_query, "highlights_query")?;

        let language = tree_sitter::Language::new(unsafe {
            tree_sitter_language::LanguageFn::from_raw(language_fn)
        });

        let mut config =
            TreeSitterProcessorConfig::new(TreeSitterLanguage::native(language), highlights_query);
        if let Some(folds_query) = optional_string(folds_query, "folds_query")?
            && !folds_query.trim().is_empty()
        {
            config = config.with_folds_query(folds_query);
        }

        if let Some(capture_styles_json) =
            optional_string(capture_styles_json, "capture_styles_json")?
        {
            let capture_styles: BTreeMap<String, u32> =
                parse_json(&capture_styles_json, "capture styles")?;
            config.capture_styles = capture_styles;
        }

        config.style_layer = StyleLayerId::new(style_layer);
        config.set_preserve_collapsed_folds(preserve_collapsed_folds);

        let processor = TreeSitterProcessor::new(config)
            .map_err(|err| format!("failed to create tree-sitter processor: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterProcessor {
            inner: processor,
        })))
    })
}

/// Create a Tree-sitter WASM processor from a grammar file path.
///
/// This is useful for FFI consumers that want to avoid shipping native Tree-sitter grammars as
/// compiled-in dependencies.
///
/// `capture_styles_json` is optional object JSON: `{ "capture.name": 123, ... }`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_new_wasm_from_path(
    language_id_utf8: *const c_char,
    wasm_path_utf8: *const c_char,
    highlights_query: *const c_char,
    folds_query: *const c_char,
    capture_styles_json: *const c_char,
    style_layer: u32,
    preserve_collapsed_folds: bool,
) -> *mut EcfTreeSitterProcessor {
    result_ptr(ptr::null_mut(), || {
        let language_id = require_string(language_id_utf8, "language_id_utf8")?;
        let wasm_path = require_string(wasm_path_utf8, "wasm_path_utf8")?;
        let highlights_query = require_string(highlights_query, "highlights_query")?;

        let wasm_bytes = std::fs::read(&wasm_path)
            .map_err(|e| format!("failed to read wasm file '{}': {e}", wasm_path))?;

        let mut config = TreeSitterProcessorConfig::new(
            TreeSitterLanguage::wasm(language_id, wasm_bytes),
            highlights_query,
        );

        if let Some(folds_query) = optional_string(folds_query, "folds_query")?
            && !folds_query.trim().is_empty()
        {
            config = config.with_folds_query(folds_query);
        }

        if let Some(capture_styles_json) =
            optional_string(capture_styles_json, "capture_styles_json")?
        {
            let capture_styles: BTreeMap<String, u32> =
                parse_json(&capture_styles_json, "capture styles")?;
            config.capture_styles = capture_styles;
        }

        config.style_layer = StyleLayerId::new(style_layer);
        config.set_preserve_collapsed_folds(preserve_collapsed_folds);

        let processor = TreeSitterProcessor::new(config)
            .map_err(|err| format!("failed to create tree-sitter processor: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterProcessor {
            inner: processor,
        })))
    })
}

/// Destroy a Tree-sitter processor.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_treesitter_processor_free(
    processor: *mut EcfTreeSitterProcessor,
) {
    if processor.is_null() {
        return;
    }
    // SAFETY: pointer must come from constructor in this crate.
    unsafe {
        drop(Box::from_raw(processor));
    }
}

/// Run Tree-sitter processing and return generated processing edits JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_process_json(
    processor: *mut EcfTreeSitterProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_mut(processor, "processor")?;
        let state = require_ref(state, "state")?;
        let edits = processor
            .inner
            .process(&state.inner)
            .map_err(|err| format!("tree-sitter process failed: {err}"))?;
        Ok(json!({
            "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
        }))
    })
}

/// Run Tree-sitter processor and apply edits to state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_apply(
    processor: *mut EcfTreeSitterProcessor,
    state: *mut EcfEditorState,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let state = require_mut(state, "state")?;
        state
            .inner
            .apply_processor(&mut processor.inner)
            .map_err(|err| format!("tree-sitter apply failed: {err}"))?;
        Ok(true)
    })
}

/// Get Tree-sitter processor last update mode.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_last_update_mode_json(
    processor: *const EcfTreeSitterProcessor,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_ref(processor, "processor")?;
        let mode = match processor.inner.last_update_mode() {
            TreeSitterUpdateMode::Initial => "initial",
            TreeSitterUpdateMode::Incremental => "incremental",
            TreeSitterUpdateMode::FullReparse => "full_reparse",
            TreeSitterUpdateMode::Skipped => "skipped",
        };
        Ok(json!({ "mode": mode }))
    })
}

/// Create a Tree-sitter indenter from a native grammar function.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_new(
    language_fn: Option<EcfTreeSitterLanguageFn>,
    indents_query: *const c_char,
) -> *mut EcfTreeSitterIndenter {
    result_ptr(ptr::null_mut(), || {
        let language_fn = language_fn.ok_or_else(|| "language_fn is null".to_string())?;
        let indents_query = require_string(indents_query, "indents_query")?;

        let language = tree_sitter::Language::new(unsafe {
            tree_sitter_language::LanguageFn::from_raw(language_fn)
        });

        let config =
            TreeSitterIndenterConfig::new(TreeSitterLanguage::native(language), indents_query);
        let indenter = TreeSitterIndenter::new(config)
            .map_err(|err| format!("failed to create tree-sitter indenter: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterIndenter {
            inner: indenter,
        })))
    })
}

/// Create a Tree-sitter indenter from a WASM grammar file path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_new_wasm_from_path(
    language_id_utf8: *const c_char,
    wasm_path_utf8: *const c_char,
    indents_query: *const c_char,
) -> *mut EcfTreeSitterIndenter {
    result_ptr(ptr::null_mut(), || {
        let language_id = require_string(language_id_utf8, "language_id_utf8")?;
        let wasm_path = require_string(wasm_path_utf8, "wasm_path_utf8")?;
        let indents_query = require_string(indents_query, "indents_query")?;

        let wasm_bytes = std::fs::read(&wasm_path)
            .map_err(|e| format!("failed to read wasm file '{}': {e}", wasm_path))?;

        let config = TreeSitterIndenterConfig::new(
            TreeSitterLanguage::wasm(language_id, wasm_bytes),
            indents_query,
        );
        let indenter = TreeSitterIndenter::new(config)
            .map_err(|err| format!("failed to create tree-sitter indenter: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterIndenter {
            inner: indenter,
        })))
    })
}

/// Destroy a Tree-sitter indenter.
///
/// # Safety
///
/// `indenter` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_treesitter_indenter_free(
    indenter: *mut EcfTreeSitterIndenter,
) {
    if indenter.is_null() {
        return;
    }
    // SAFETY: pointer must come from constructor in this crate.
    unsafe {
        drop(Box::from_raw(indenter));
    }
}

/// Compute a reindent `TextEditSpec` for a given logical line using a Tree-sitter indenter.
///
/// - `indentation_config_json` is optional (nullable). When null, `IndentationConfig::default()` is used.
/// - The indenter is synchronized from the full document text on each call (skipped when the
///   editor version is unchanged).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_reindent_line_json(
    indenter: *mut EcfTreeSitterIndenter,
    state: *const EcfEditorState,
    line: u32,
    indentation_config_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let indenter = require_mut(indenter, "indenter")?;
        let state = require_ref(state, "state")?;
        let line = usize_from_u32(line, "line")?;

        let cfg = if let Some(json_text) =
            optional_string(indentation_config_json, "indentation_config_json")?
        {
            let parsed: FfiIndentationConfig = parse_json(&json_text, "indentation config")?;
            IndentationConfig::from(parsed)
        } else {
            IndentationConfig::default()
        };

        let text = state.inner.editor().get_text();
        indenter
            .inner
            .sync_to_text(state.inner.version(), &text)
            .map_err(|err| format!("treesitter indenter sync failed: {err}"))?;

        let edit = indenter
            .inner
            .reindent_text_edit_for_line(line, cfg.style.clone());

        Ok(json!({
            "has_edit": edit.is_some(),
            "edit": edit.map(|e| json!({ "start": e.start, "end": e.end, "text": e.text })),
        }))
    })
}
