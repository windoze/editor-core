#ifndef EDITOR_CORE_FFI_H
#define EDITOR_CORE_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EcfEditorState EcfEditorState;
typedef struct EcfWorkspace EcfWorkspace;
typedef struct EcfSublimeProcessor EcfSublimeProcessor;
typedef struct EcfTreeSitterProcessor EcfTreeSitterProcessor;

typedef const void* (*EcfTreeSitterLanguageFn)(void);

typedef enum EcfStatus {
    ECF_OK = 0,
    ECF_ERR_INVALID_ARGUMENT = 1,
    ECF_ERR_INVALID_UTF8 = 2,
    ECF_ERR_NOT_FOUND = 3,
    ECF_ERR_BUFFER_TOO_SMALL = 4,
    ECF_ERR_PARSE = 5,
    ECF_ERR_COMMAND_FAILED = 6,
    ECF_ERR_INTERNAL = 7,
    ECF_ERR_UNSUPPORTED = 8,
    ECF_ERR_VERSION_MISMATCH = 9,
} EcfStatus;

typedef struct EcfViewportBlobHeader {
    uint32_t abi_version;
    uint32_t header_size;
    uint32_t line_count;
    uint32_t cell_count;
    uint32_t style_id_count;
    uint32_t lines_offset;
    uint32_t cells_offset;
    uint32_t style_ids_offset;
    uint32_t reserved;
} EcfViewportBlobHeader;

typedef struct EcfViewportLine {
    uint32_t logical_line_index;
    uint32_t visual_in_logical;
    uint32_t char_offset_start;
    uint32_t char_offset_end;
    uint32_t cell_start_index;
    uint32_t cell_count;
    uint16_t segment_x_start_cells;
    uint8_t is_wrapped_part;
    uint8_t is_fold_placeholder_appended;
} EcfViewportLine;

typedef struct EcfViewportCell {
    uint32_t scalar_value;
    uint16_t width;
    uint16_t style_count;
    uint32_t style_start_index;
} EcfViewportCell;

typedef struct EcfDocumentStats {
    uint32_t abi_version;
    uint32_t struct_size;
    uint64_t line_count;
    uint64_t char_count;
    uint64_t byte_count;
    uint8_t is_modified;
    uint8_t reserved0[7];
    uint64_t version;
} EcfDocumentStats;

uint32_t editor_core_ffi_abi_version(void);
char* editor_core_ffi_version(void);
char* editor_core_ffi_last_error_message(void);
void editor_core_ffi_string_free(char* ptr);

EcfEditorState* editor_core_ffi_editor_state_new(const char* initial_text, size_t viewport_width);
void editor_core_ffi_editor_state_free(EcfEditorState* state);
char* editor_core_ffi_editor_state_execute_json(EcfEditorState* state, const char* command_json);
bool editor_core_ffi_editor_state_apply_processing_edits_json(EcfEditorState* state, const char* edits_json);
char* editor_core_ffi_editor_state_full_state_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_text(const EcfEditorState* state);
char* editor_core_ffi_editor_state_text_for_saving(const EcfEditorState* state);
char* editor_core_ffi_editor_state_document_symbols_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_diagnostics_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_decorations_json(const EcfEditorState* state);
bool editor_core_ffi_editor_state_set_line_ending(EcfEditorState* state, const char* line_ending);
char* editor_core_ffi_editor_state_get_line_ending(const EcfEditorState* state);
char* editor_core_ffi_editor_state_viewport_styled_json(const EcfEditorState* state, size_t start_visual_row, size_t count);
char* editor_core_ffi_editor_state_minimap_json(const EcfEditorState* state, size_t start_visual_row, size_t count);
char* editor_core_ffi_editor_state_viewport_composed_json(const EcfEditorState* state, size_t start_visual_row, size_t count);
char* editor_core_ffi_editor_state_take_last_text_delta_json(EcfEditorState* state);
char* editor_core_ffi_editor_state_last_text_delta_json(const EcfEditorState* state);
int32_t editor_core_ffi_editor_get_document_stats(const EcfEditorState* state, EcfDocumentStats* out_stats);
int32_t editor_core_ffi_editor_insert_text_utf8(EcfEditorState* state, const uint8_t* bytes, uint32_t len);
int32_t editor_core_ffi_editor_backspace(EcfEditorState* state);
int32_t editor_core_ffi_editor_delete_forward(EcfEditorState* state);
int32_t editor_core_ffi_editor_undo(EcfEditorState* state);
int32_t editor_core_ffi_editor_redo(EcfEditorState* state);
int32_t editor_core_ffi_editor_move_to(EcfEditorState* state, uint32_t line, uint32_t column);
int32_t editor_core_ffi_editor_move_by(EcfEditorState* state, int32_t delta_line, int32_t delta_column);
int32_t editor_core_ffi_editor_set_selection(
    EcfEditorState* state,
    uint32_t start_line,
    uint32_t start_column,
    uint32_t end_line,
    uint32_t end_column,
    uint8_t direction);
int32_t editor_core_ffi_editor_clear_selection(EcfEditorState* state);
int32_t editor_core_ffi_editor_get_viewport_blob(
    const EcfEditorState* state,
    uint32_t start_visual_row,
    uint32_t row_count,
    uint8_t* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);

EcfWorkspace* editor_core_ffi_workspace_new(void);
void editor_core_ffi_workspace_free(EcfWorkspace* workspace);
char* editor_core_ffi_workspace_open_buffer(EcfWorkspace* workspace, const char* uri, const char* text, size_t viewport_width);
bool editor_core_ffi_workspace_close_buffer(EcfWorkspace* workspace, uint64_t buffer_id);
bool editor_core_ffi_workspace_close_view(EcfWorkspace* workspace, uint64_t view_id);
char* editor_core_ffi_workspace_create_view(EcfWorkspace* workspace, uint64_t buffer_id, size_t viewport_width);
bool editor_core_ffi_workspace_set_active_view(EcfWorkspace* workspace, uint64_t view_id);
char* editor_core_ffi_workspace_info_json(const EcfWorkspace* workspace);
char* editor_core_ffi_workspace_execute_json(EcfWorkspace* workspace, uint64_t view_id, const char* command_json);
bool editor_core_ffi_workspace_apply_processing_edits_json(EcfWorkspace* workspace, uint64_t buffer_id, const char* edits_json);
char* editor_core_ffi_workspace_buffer_text_json(const EcfWorkspace* workspace, uint64_t buffer_id);
char* editor_core_ffi_workspace_viewport_state_json(EcfWorkspace* workspace, uint64_t view_id);
bool editor_core_ffi_workspace_set_viewport_height(EcfWorkspace* workspace, uint64_t view_id, size_t height);
bool editor_core_ffi_workspace_set_smooth_scroll_state(EcfWorkspace* workspace, uint64_t view_id, size_t top_visual_row, uint16_t sub_row_offset, size_t overscan_rows);
char* editor_core_ffi_workspace_viewport_styled_json(EcfWorkspace* workspace, uint64_t view_id, size_t start_visual_row, size_t count);
char* editor_core_ffi_workspace_minimap_json(EcfWorkspace* workspace, uint64_t view_id, size_t start_visual_row, size_t count);
char* editor_core_ffi_workspace_viewport_composed_json(EcfWorkspace* workspace, uint64_t view_id, size_t start_visual_row, size_t count);
char* editor_core_ffi_workspace_search_all_open_buffers_json(const EcfWorkspace* workspace, const char* query, const char* options_json);
char* editor_core_ffi_workspace_apply_text_edits_json(EcfWorkspace* workspace, const char* edits_json);
int32_t editor_core_ffi_workspace_insert_text_utf8(EcfWorkspace* workspace, uint64_t view_id, const uint8_t* bytes, uint32_t len);
int32_t editor_core_ffi_workspace_move_to(EcfWorkspace* workspace, uint64_t view_id, uint32_t line, uint32_t column);
int32_t editor_core_ffi_workspace_backspace(EcfWorkspace* workspace, uint64_t view_id);
int32_t editor_core_ffi_workspace_get_viewport_blob(
    EcfWorkspace* workspace,
    uint64_t view_id,
    uint32_t start_visual_row,
    uint32_t row_count,
    uint8_t* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);

char* editor_core_ffi_lsp_path_to_file_uri(const char* path);
char* editor_core_ffi_lsp_file_uri_to_path(const char* uri);
char* editor_core_ffi_lsp_percent_encode_path(const char* path);
char* editor_core_ffi_lsp_percent_decode_path(const char* path);
size_t editor_core_ffi_lsp_char_offset_to_utf16(const char* line_text, size_t char_offset);
size_t editor_core_ffi_lsp_utf16_to_char_offset(const char* line_text, size_t utf16_offset);
char* editor_core_ffi_lsp_apply_text_edits_json(EcfEditorState* state, const char* edits_json);
char* editor_core_ffi_lsp_semantic_tokens_to_intervals_json(const EcfEditorState* state, const char* data_json);
char* editor_core_ffi_lsp_decode_semantic_style_id(uint32_t style_id);
char* editor_core_ffi_lsp_document_highlights_to_processing_edit_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_inlay_hints_to_processing_edit_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_document_links_to_processing_edit_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_code_lens_to_processing_edit_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_document_symbols_to_processing_edit_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_diagnostics_to_processing_edits_json(const EcfEditorState* state, const char* publish_diagnostics_params_json);
char* editor_core_ffi_lsp_workspace_symbols_json(const char* result_json);
char* editor_core_ffi_lsp_locations_json(const char* result_json);
char* editor_core_ffi_lsp_completion_item_to_text_edits_json(const EcfEditorState* state, const char* completion_item_json, const char* mode, size_t fallback_start, size_t fallback_end, bool has_fallback);
bool editor_core_ffi_lsp_apply_completion_item_json(EcfEditorState* state, const char* completion_item_json, const char* mode);
uint32_t editor_core_ffi_lsp_encode_semantic_style_id(uint32_t token_type, uint32_t token_modifiers);

EcfSublimeProcessor* editor_core_ffi_sublime_processor_new_from_yaml(const char* yaml);
EcfSublimeProcessor* editor_core_ffi_sublime_processor_new_from_path(const char* path);
void editor_core_ffi_sublime_processor_free(EcfSublimeProcessor* processor);
bool editor_core_ffi_sublime_processor_add_search_path(EcfSublimeProcessor* processor, const char* path);
bool editor_core_ffi_sublime_processor_load_syntax_from_yaml(EcfSublimeProcessor* processor, const char* yaml);
bool editor_core_ffi_sublime_processor_load_syntax_from_path(EcfSublimeProcessor* processor, const char* path);
bool editor_core_ffi_sublime_processor_set_active_syntax_by_reference(EcfSublimeProcessor* processor, const char* reference);
bool editor_core_ffi_sublime_processor_set_preserve_collapsed_folds(EcfSublimeProcessor* processor, bool preserve);
char* editor_core_ffi_sublime_processor_process_json(EcfSublimeProcessor* processor, const EcfEditorState* state);
bool editor_core_ffi_sublime_processor_apply(EcfSublimeProcessor* processor, EcfEditorState* state);
char* editor_core_ffi_sublime_processor_scope_for_style_id(const EcfSublimeProcessor* processor, uint32_t style_id);

EcfTreeSitterProcessor* editor_core_ffi_treesitter_processor_new(
    EcfTreeSitterLanguageFn language_fn,
    const char* highlights_query,
    const char* folds_query,
    const char* capture_styles_json,
    uint32_t style_layer,
    bool preserve_collapsed_folds);

/* Built-in Tree-sitter Rust language */
const void* editor_core_ffi_treesitter_language_rust(void);

void editor_core_ffi_treesitter_processor_free(EcfTreeSitterProcessor* processor);
char* editor_core_ffi_treesitter_processor_process_json(EcfTreeSitterProcessor* processor, const EcfEditorState* state);
bool editor_core_ffi_treesitter_processor_apply(EcfTreeSitterProcessor* processor, EcfEditorState* state);
char* editor_core_ffi_treesitter_processor_last_update_mode_json(const EcfTreeSitterProcessor* processor);

/* ABI-v1 short aliases */
uint32_t ecf_abi_version(void);
int32_t ecf_editor_insert_text_utf8(EcfEditorState* state, const uint8_t* bytes, uint32_t len);
int32_t ecf_editor_move_to(EcfEditorState* state, uint32_t line, uint32_t column);
int32_t ecf_editor_backspace(EcfEditorState* state);
int32_t ecf_editor_get_viewport_blob(
    const EcfEditorState* state,
    uint32_t start_visual_row,
    uint32_t row_count,
    uint8_t* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);

#ifdef __cplusplus
}
#endif

#endif // EDITOR_CORE_FFI_H
