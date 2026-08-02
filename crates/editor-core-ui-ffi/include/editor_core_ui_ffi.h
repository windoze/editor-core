#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle.
typedef struct EditorUi EditorUi;
typedef struct MultiDocumentEditorUi MultiDocumentEditorUi;

typedef struct EcuRgba8 {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} EcuRgba8;

typedef struct EcuTheme {
  EcuRgba8 background;
  EcuRgba8 foreground;
  EcuRgba8 selection_background;
  EcuRgba8 caret;
} EcuTheme;

typedef struct EcuChromeTheme {
  EcuRgba8 gutter_background;
  EcuRgba8 gutter_foreground;
  EcuRgba8 gutter_separator;
  EcuRgba8 fold_marker_collapsed;
  EcuRgba8 fold_marker_expanded;
} EcuChromeTheme;

typedef enum EcuTextVerticalAlign {
  // 0=top, 1=center, 2=bottom (kept stable for ABI)
  ECU_TEXT_VERTICAL_ALIGN_TOP = 0,
  ECU_TEXT_VERTICAL_ALIGN_CENTER = 1,
  ECU_TEXT_VERTICAL_ALIGN_BOTTOM = 2,
} EcuTextVerticalAlign;

typedef enum EcuTabKeyBehavior {
  // 0=tab, 1=spaces (kept stable for ABI)
  ECU_TAB_KEY_BEHAVIOR_TAB = 0,
  ECU_TAB_KEY_BEHAVIOR_SPACES = 1,
} EcuTabKeyBehavior;

// A single StyleId override entry.
//
// flags bitmask:
// - bit 0: foreground present
// - bit 1: background present
typedef struct EcuStyleColors {
  uint32_t style_id;
  uint32_t flags;
  EcuRgba8 foreground;
  EcuRgba8 background;
} EcuStyleColors;

typedef enum EcuUnderlineStyle {
  // 1=single, 2=double, 3=squiggly (0 is reserved)
  ECU_UNDERLINE_STYLE_SINGLE = 1,
  ECU_UNDERLINE_STYLE_DOUBLE = 2,
  ECU_UNDERLINE_STYLE_SQUIGGLY = 3,
} EcuUnderlineStyle;

// A single StyleId text-decoration override entry.
//
// flags bitmask:
// - bit 0: underline style present
// - bit 1: underline color present
// - bit 2: strikethrough present
// - bit 3: strikethrough color present
//
// underline_style values: see `EcuUnderlineStyle`.
// strikethrough values: 0=disabled, 1=enabled.
typedef struct EcuStyleTextDecorations {
  uint32_t style_id;
  uint32_t flags;
  uint32_t underline_style;
  EcuRgba8 underline_color;
  uint32_t strikethrough;
  EcuRgba8 strikethrough_color;
} EcuStyleTextDecorations;

// A single StyleId font-style override entry.
//
// flags bitmask:
// - bit 0: bold present
// - bit 1: italic present
//
// bold / italic values: 0=disabled, 1=enabled.
typedef struct EcuStyleFont {
  uint32_t style_id;
  uint32_t flags;
  uint32_t bold;
  uint32_t italic;
} EcuStyleFont;

typedef struct EcuSelectionRange {
  uint32_t start;
  uint32_t end;
} EcuSelectionRange;

// Viewport state snapshot.
//
// Notes:
// - `height_rows` is optional in the Rust core. In the UI wrapper it should always be set
//   (because the host provides a pixel viewport), but the ABI keeps this optional so
//   non-UI hosts can still query it.
// - All values are expressed in logical row units (visual lines after wrapping/folding),
//   except `sub_row_offset` which is a normalized 0..=65535 fraction within a row.
typedef struct EcuViewportState {
  uint32_t width_cells;
  uint32_t height_rows;
  uint32_t has_height;
  uint32_t scroll_top;
  uint32_t sub_row_offset;
  uint32_t overscan_rows;
  uint32_t visible_start;
  uint32_t visible_end;
  uint32_t prefetch_start;
  uint32_t prefetch_end;
  uint32_t total_visual_lines;
} EcuViewportState;

// Return codes (int32).
// 0 = OK
// 1 = invalid argument
// 4 = buffer too small (out_len contains required size)
// 7 = internal error (check last_error_message)

void editor_core_ui_ffi_string_free(char* ptr);
char* editor_core_ui_ffi_last_error_message(void);
char* editor_core_ui_ffi_version(void);
uint32_t editor_core_ui_ffi_abi_version(void);

// Feature flags returned by `editor_core_ui_ffi_feature_flags`.
#define ECU_FEATURE_JSON_COMMAND_DISPATCH      (1ull << 0)
#define ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS    (1ull << 1)
#define ECU_FEATURE_LSP_INTERACTIVE_REQUESTS   (1ull << 2)
#define ECU_FEATURE_LSP_STATUS_SNAPSHOT        (1ull << 3)
#define ECU_FEATURE_WORKSPACE_EDIT_APPLICATION (1ull << 4)
#define ECU_FEATURE_MULTI_DOCUMENT_UI          (1ull << 5)
#define ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE (1ull << 6)
#define ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS (1ull << 7)
#define ECU_FEATURE_LSP_RESULT_EVENTS          (1ull << 8)
#define ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS (1ull << 9)
#define ECU_FEATURE_LSP_REQUEST_EVENTS         (1ull << 10)
#define ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS (1ull << 11)
#define ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS (1ull << 12)
#define ECU_FEATURE_LSP_SEMANTIC_TOKENS_REQUESTS (1ull << 13)
#define ECU_FEATURE_LSP_AUXILIARY_REQUESTS    (1ull << 14)
#define ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS (1ull << 15)
#define ECU_FEATURE_EDITOR_UI_STATE_EVENTS    (1ull << 16)
#define ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS (1ull << 17)
#define ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT (1ull << 18)
uint64_t editor_core_ui_ffi_feature_flags(void);

MultiDocumentEditorUi* editor_core_ui_ffi_multi_document_new(void);
void editor_core_ui_ffi_multi_document_free(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_open_tab(MultiDocumentEditorUi* multi,
                                                   const char* initial_text_utf8,
                                                   uint32_t viewport_width_cells,
                                                   uint64_t* out_tab_id);
int32_t editor_core_ui_ffi_multi_document_open_preview_tab(MultiDocumentEditorUi* multi,
                                                           const char* initial_text_utf8,
                                                           uint32_t viewport_width_cells,
                                                           uint64_t* out_tab_id);
int32_t editor_core_ui_ffi_multi_document_active_tab_id(MultiDocumentEditorUi* multi,
                                                        uint8_t* out_has_active,
                                                        uint64_t* out_tab_id);
char* editor_core_ui_ffi_multi_document_snapshot_json(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_set_active_tab(MultiDocumentEditorUi* multi,
                                                         uint64_t tab_id);
int32_t editor_core_ui_ffi_multi_document_set_tab_title(MultiDocumentEditorUi* multi,
                                                        uint64_t tab_id,
                                                        const char* title_utf8);
int32_t editor_core_ui_ffi_multi_document_is_preview_tab(MultiDocumentEditorUi* multi,
                                                         uint64_t tab_id,
                                                         uint8_t* out_is_preview);
int32_t editor_core_ui_ffi_multi_document_pin_tab(MultiDocumentEditorUi* multi, uint64_t tab_id);
int32_t editor_core_ui_ffi_multi_document_close_tab(MultiDocumentEditorUi* multi,
                                                    uint64_t tab_id,
                                                    uint8_t* out_closed);
int32_t editor_core_ui_ffi_multi_document_close_all_tabs(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_close_other_tabs(MultiDocumentEditorUi* multi,
                                                           uint64_t tab_id,
                                                           uint32_t* out_closed_count);
int32_t editor_core_ui_ffi_multi_document_close_tabs_to_right(MultiDocumentEditorUi* multi,
                                                              uint64_t tab_id,
                                                              uint32_t* out_closed_count);
int32_t editor_core_ui_ffi_multi_document_move_tab_index(MultiDocumentEditorUi* multi,
                                                         uint32_t from_tab_index,
                                                         uint32_t to_tab_index,
                                                         uint8_t* out_moved);
int32_t editor_core_ui_ffi_multi_document_split_tab(MultiDocumentEditorUi* multi,
                                                    uint64_t tab_id,
                                                    uint32_t viewport_width_cells,
                                                    uint32_t* out_view_index);
int32_t editor_core_ui_ffi_multi_document_set_active_view_index(MultiDocumentEditorUi* multi,
                                                                uint64_t tab_id,
                                                                uint32_t view_index);
int32_t editor_core_ui_ffi_multi_document_close_view_index(MultiDocumentEditorUi* multi,
                                                           uint64_t tab_id,
                                                           uint32_t view_index,
                                                           uint8_t* out_closed);
int32_t editor_core_ui_ffi_multi_document_move_view_index(MultiDocumentEditorUi* multi,
                                                          uint64_t tab_id,
                                                          uint32_t from_view_index,
                                                          uint32_t to_view_index,
                                                          uint8_t* out_moved);
int32_t editor_core_ui_ffi_multi_document_view_count(MultiDocumentEditorUi* multi,
                                                     uint64_t tab_id,
                                                     uint32_t* out_view_count);
char* editor_core_ui_ffi_multi_document_tab_text(MultiDocumentEditorUi* multi,
                                                 uint64_t tab_id);
int32_t editor_core_ui_ffi_multi_document_replace_tab_text(MultiDocumentEditorUi* multi,
                                                           uint64_t tab_id,
                                                           const char* text_utf8,
                                                           uint8_t mark_saved);
int32_t editor_core_ui_ffi_multi_document_is_tab_modified(MultiDocumentEditorUi* multi,
                                                          uint64_t tab_id,
                                                          uint8_t* out_modified);
int32_t editor_core_ui_ffi_multi_document_mark_tab_saved(MultiDocumentEditorUi* multi,
                                                         uint64_t tab_id);
char* editor_core_ui_ffi_multi_document_search_all_tabs_json(MultiDocumentEditorUi* multi,
                                                             const char* query_utf8,
                                                             uint8_t case_sensitive,
                                                             uint8_t whole_word,
                                                             uint8_t regex);
char* editor_core_ui_ffi_multi_document_workspace_outline_snapshot_json(
    MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_apply_tab_document_symbols_json(
    MultiDocumentEditorUi* multi,
    uint64_t tab_id,
    const char* result_json_utf8);
char* editor_core_ui_ffi_multi_document_apply_workspace_diagnostics_json(
    MultiDocumentEditorUi* multi,
    const char* result_json_utf8);
char* editor_core_ui_ffi_multi_document_workspace_diagnostics_snapshot_json(
    MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_workspace_diagnostic_markers_json(
    MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_workspace_diagnostics_previous_result_ids_json(
    MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_workspace_diagnostics_latest_event_sequence(
    MultiDocumentEditorUi* multi,
    uint64_t* out_sequence);
char* editor_core_ui_ffi_multi_document_workspace_diagnostics_events_json(
    MultiDocumentEditorUi* multi,
    uint64_t after_sequence);
int32_t editor_core_ui_ffi_multi_document_lsp_result_events_latest_sequence(
    MultiDocumentEditorUi* multi,
    uint64_t* out_sequence);
char* editor_core_ui_ffi_multi_document_lsp_result_events_json(MultiDocumentEditorUi* multi,
                                                               uint64_t after_sequence);
int32_t editor_core_ui_ffi_multi_document_lsp_request_events_latest_sequence(
    MultiDocumentEditorUi* multi,
    uint64_t* out_sequence);
char* editor_core_ui_ffi_multi_document_lsp_request_events_json(MultiDocumentEditorUi* multi,
                                                                uint64_t after_sequence);
int32_t editor_core_ui_ffi_multi_document_state_events_latest_sequence(
    MultiDocumentEditorUi* multi,
    uint64_t* out_sequence);
char* editor_core_ui_ffi_multi_document_state_events_json(MultiDocumentEditorUi* multi,
                                                          uint64_t after_sequence);
int32_t editor_core_ui_ffi_multi_document_clear_workspace_diagnostics(
    MultiDocumentEditorUi* multi);

EditorUi* editor_core_ui_ffi_editor_ui_new(const char* initial_text_utf8,
                                          uint32_t viewport_width_cells);
// Create a new view handle that shares the same document/buffer with `ui`.
//
// The returned handle must be freed with `editor_core_ui_ffi_editor_ui_free`.
EditorUi* editor_core_ui_ffi_editor_ui_clone_view(EditorUi* ui,
                                                  uint32_t viewport_width_cells);
void editor_core_ui_ffi_editor_ui_free(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_set_theme(EditorUi* ui, const EcuTheme* theme);
int32_t editor_core_ui_ffi_editor_ui_set_chrome_theme(EditorUi* ui, const EcuChromeTheme* theme);
int32_t editor_core_ui_ffi_editor_ui_set_style_colors(EditorUi* ui,
                                                      const EcuStyleColors* styles,
                                                      uint32_t style_count);
int32_t editor_core_ui_ffi_editor_ui_set_style_fonts(EditorUi* ui,
                                                     const EcuStyleFont* fonts,
                                                     uint32_t font_count);
int32_t editor_core_ui_ffi_editor_ui_set_style_text_decorations(
    EditorUi* ui,
    const EcuStyleTextDecorations* decorations,
    uint32_t decoration_count
);

// Sublime syntax integration (highlighting + folding).
int32_t editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(EditorUi* ui, const char* yaml_utf8);
int32_t editor_core_ui_ffi_editor_ui_sublime_set_syntax_path(EditorUi* ui, const char* path_utf8);
void editor_core_ui_ffi_editor_ui_sublime_disable(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(EditorUi* ui,
                                                                const char* scope_utf8,
                                                                uint32_t* out_style_id);
char* editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(EditorUi* ui, uint32_t style_id);

// Tree-sitter integration (highlighting + folding).
int32_t editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(
    EditorUi* ui,
    const char* registry_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_treesitter_enable_language(EditorUi* ui,
                                                                const char* language_id_utf8);
int32_t editor_core_ui_ffi_editor_ui_treesitter_enable_for_path(EditorUi* ui,
                                                                const char* path_utf8);
int32_t editor_core_ui_ffi_editor_ui_treesitter_enable_query_pack(EditorUi* ui,
                                                                  const char* pack_id_utf8);
int32_t editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(EditorUi* ui);
void editor_core_ui_ffi_editor_ui_treesitter_disable(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_poll_processing(EditorUi* ui,
                                                     uint8_t* out_applied,
                                                     uint8_t* out_pending);
int32_t editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(EditorUi* ui,
                                                                     const char* capture_utf8,
                                                                     uint32_t* out_style_id);
char* editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(EditorUi* ui, uint32_t style_id);

// LSP integration (optional; stdio session managed by Rust).
int32_t editor_core_ui_ffi_editor_ui_lsp_enable(EditorUi* ui,
                                               const char* cmd_utf8,
                                               const char* args_utf8, // nullable, split by whitespace
                                               const char* root_uri_utf8,
                                               const char* doc_uri_utf8,
                                               const char* language_id_utf8);
void editor_core_ui_ffi_editor_ui_lsp_disable(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_lsp_is_enabled(EditorUi* ui, uint8_t* out_enabled);
int32_t editor_core_ui_ffi_editor_ui_lsp_status_json(EditorUi* ui, char** out_status_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_result_events_latest_sequence(EditorUi* ui,
                                                                        uint64_t* out_sequence);
char* editor_core_ui_ffi_editor_ui_lsp_result_events_json(EditorUi* ui, uint64_t after_sequence);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_events_latest_sequence(EditorUi* ui,
                                                                        uint64_t* out_sequence);
char* editor_core_ui_ffi_editor_ui_lsp_request_events_json(EditorUi* ui,
                                                           uint64_t after_sequence);
int32_t editor_core_ui_ffi_editor_ui_state_events_latest_sequence(EditorUi* ui,
                                                                  uint64_t* out_sequence);
char* editor_core_ui_ffi_editor_ui_state_events_json(EditorUi* ui,
                                                     uint64_t after_sequence);
int32_t editor_core_ui_ffi_editor_ui_lsp_cancel_request(EditorUi* ui,
                                                        uint64_t request_id,
                                                        uint8_t* out_recorded);
int32_t editor_core_ui_ffi_editor_ui_lsp_mark_request_timed_out(EditorUi* ui,
                                                                uint64_t request_id,
                                                                uint8_t* out_recorded);

// LSP interactive requests (optional; demo UX).
//
// These APIs are non-blocking: they enqueue an LSP request and store the result internally.
// Hosts should poll via `editor_core_ui_ffi_editor_ui_poll_processing` and then read the latest
// result via the corresponding `take_*` function.
int32_t editor_core_ui_ffi_editor_ui_lsp_request_hover(EditorUi* ui,
                                                       uint32_t line,
                                                       uint32_t column,
                                                       uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(EditorUi* ui,
                                                              uint8_t* out_has_result,
                                                              char** out_result_json_utf8);

int32_t editor_core_ui_ffi_editor_ui_lsp_request_definition(EditorUi* ui,
                                                            uint32_t line,
                                                            uint32_t column,
                                                            uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(EditorUi* ui,
                                                                   uint8_t* out_has_result,
                                                                   char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_declaration(EditorUi* ui,
                                                             uint32_t line,
                                                             uint32_t column,
                                                             uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_declaration_json(EditorUi* ui,
                                                                    uint8_t* out_has_result,
                                                                    char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_type_definition(EditorUi* ui,
                                                                 uint32_t line,
                                                                 uint32_t column,
                                                                 uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_type_definition_json(EditorUi* ui,
                                                                        uint8_t* out_has_result,
                                                                        char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_implementation(EditorUi* ui,
                                                                uint32_t line,
                                                                uint32_t column,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_implementation_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_references(EditorUi* ui,
                                                            uint32_t line,
                                                            uint32_t column,
                                                            uint8_t include_declaration,
                                                            uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_references_json(EditorUi* ui,
                                                                   uint8_t* out_has_result,
                                                                   char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_completion(EditorUi* ui,
                                                            uint32_t line,
                                                            uint32_t column,
                                                            uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_completion_json(EditorUi* ui,
                                                                   uint8_t* out_has_result,
                                                                   char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_completion_item_resolve(EditorUi* ui,
                                                                         const char* item_json_utf8,
                                                                         uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_completion_item_resolve_json(EditorUi* ui,
                                                                                uint8_t* out_has_result,
                                                                                char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_signature_help(EditorUi* ui,
                                                                uint32_t line,
                                                                uint32_t column,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_signature_help_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_prepare_rename(EditorUi* ui,
                                                                uint32_t line,
                                                                uint32_t column,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_rename_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_rename(EditorUi* ui,
                                                        uint32_t line,
                                                        uint32_t column,
                                                        const char* new_name_utf8,
                                                        uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_rename_json(EditorUi* ui,
                                                               uint8_t* out_has_result,
                                                               char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_code_action(EditorUi* ui,
                                                             uint32_t start_offset,
                                                             uint32_t end_offset,
                                                             const char* context_json_utf8,
                                                             uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_json(EditorUi* ui,
                                                                    uint8_t* out_has_result,
                                                                    char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_code_action_resolve(EditorUi* ui,
                                                                     const char* action_json_utf8,
                                                                     uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_resolve_json(EditorUi* ui,
                                                                            uint8_t* out_has_result,
                                                                            char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_execute_command(EditorUi* ui,
                                                                 const char* command_json_utf8,
                                                                 uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(EditorUi* ui,
                                                                        uint8_t* out_has_result,
                                                                        char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_code_lens(EditorUi* ui,
                                                           uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_json(EditorUi* ui,
                                                                  uint8_t* out_has_result,
                                                                  char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_code_lens_resolve(EditorUi* ui,
                                                                   const char* lens_json_utf8,
                                                                   uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_resolve_json(EditorUi* ui,
                                                                          uint8_t* out_has_result,
                                                                          char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_inlay_hints(EditorUi* ui,
                                                             uint32_t start_offset,
                                                             uint32_t end_offset,
                                                             uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hints_json(EditorUi* ui,
                                                                    uint8_t* out_has_result,
                                                                    char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_inlay_hint_resolve(EditorUi* ui,
                                                                    const char* hint_json_utf8,
                                                                    uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hint_resolve_json(EditorUi* ui,
                                                                           uint8_t* out_has_result,
                                                                           char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_links(EditorUi* ui,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_links_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_link_resolve(EditorUi* ui,
                                                                       const char* link_json_utf8,
                                                                       uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_link_resolve_json(EditorUi* ui,
                                                                              uint8_t* out_has_result,
                                                                              char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_symbols(EditorUi* ui,
                                                                  uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_symbols_json(EditorUi* ui,
                                                                         uint8_t* out_has_result,
                                                                         char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(EditorUi* ui,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_full(EditorUi* ui,
                                                                      uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_full_json(EditorUi* ui,
                                                                             uint8_t* out_has_result,
                                                                             char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_delta(EditorUi* ui,
                                                                       const char* previous_result_id_utf8,
                                                                       uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_delta_json(EditorUi* ui,
                                                                              uint8_t* out_has_result,
                                                                              char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_range(EditorUi* ui,
                                                                       uint32_t start_line,
                                                                       uint32_t start_column,
                                                                       uint32_t end_line,
                                                                       uint32_t end_column,
                                                                       uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_range_json(EditorUi* ui,
                                                                              uint8_t* out_has_result,
                                                                              char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_selection_range(EditorUi* ui,
                                                                 const char* positions_json_utf8,
                                                                 uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_selection_range_json(EditorUi* ui,
                                                                        uint8_t* out_has_result,
                                                                        char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_linked_editing_range(EditorUi* ui,
                                                                      uint32_t line,
                                                                      uint32_t column,
                                                                      uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_linked_editing_range_json(EditorUi* ui,
                                                                             uint8_t* out_has_result,
                                                                             char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(EditorUi* ui,
                                                                     const char* previous_result_id_utf8,
                                                                     uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_diagnostic_json(EditorUi* ui,
                                                                            uint8_t* out_has_result,
                                                                            char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_workspace_diagnostic(EditorUi* ui,
                                                                      const char* previous_result_ids_json_utf8,
                                                                      uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_diagnostic_json(EditorUi* ui,
                                                                             uint8_t* out_has_result,
                                                                             char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_color(EditorUi* ui,
                                                                uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_color_json(EditorUi* ui,
                                                                       uint8_t* out_has_result,
                                                                       char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_color_presentation(EditorUi* ui,
                                                                    uint32_t start_offset,
                                                                    uint32_t end_offset,
                                                                    const char* color_json_utf8,
                                                                    uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_color_presentation_json(EditorUi* ui,
                                                                           uint8_t* out_has_result,
                                                                           char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_prepare_call_hierarchy(EditorUi* ui,
                                                                        uint32_t line,
                                                                        uint32_t column,
                                                                        uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_call_hierarchy_json(EditorUi* ui,
                                                                               uint8_t* out_has_result,
                                                                               char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_incoming_calls(EditorUi* ui,
                                                                               const char* item_json_utf8,
                                                                               uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json(EditorUi* ui,
                                                                                      uint8_t* out_has_result,
                                                                                      char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_outgoing_calls(EditorUi* ui,
                                                                               const char* item_json_utf8,
                                                                               uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json(EditorUi* ui,
                                                                                      uint8_t* out_has_result,
                                                                                      char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_prepare_type_hierarchy(EditorUi* ui,
                                                                        uint32_t line,
                                                                        uint32_t column,
                                                                        uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_type_hierarchy_json(EditorUi* ui,
                                                                               uint8_t* out_has_result,
                                                                               char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_supertypes(EditorUi* ui,
                                                                           const char* item_json_utf8,
                                                                           uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_supertypes_json(EditorUi* ui,
                                                                                  uint8_t* out_has_result,
                                                                                  char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_subtypes(EditorUi* ui,
                                                                         const char* item_json_utf8,
                                                                         uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_subtypes_json(EditorUi* ui,
                                                                                uint8_t* out_has_result,
                                                                                char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_workspace_symbols(EditorUi* ui,
                                                                   const char* query_utf8,
                                                                   uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_symbols_json(EditorUi* ui,
                                                                          uint8_t* out_has_result,
                                                                          char** out_result_json_utf8);

// LSP "turnkey" helpers (blocking user actions).
int32_t editor_core_ui_ffi_editor_ui_lsp_format_document(
    EditorUi* ui,
    const char* formatting_options_json_utf8, // nullable
    uint32_t timeout_ms,
    uint8_t* out_applied
);
int32_t editor_core_ui_ffi_editor_ui_lsp_format_range(
    EditorUi* ui,
    uint32_t start_offset,
    uint32_t end_offset,
    const char* formatting_options_json_utf8, // nullable
    uint32_t timeout_ms,
    uint8_t* out_applied
);
int32_t editor_core_ui_ffi_editor_ui_lsp_format_on_type(
    EditorUi* ui,
    uint32_t logical_line,
    uint32_t logical_column,
    const char* trigger_utf8,
    const char* formatting_options_json_utf8, // nullable
    uint32_t timeout_ms,
    uint8_t* out_applied
);

// LSP-derived state ingestion.
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(
    EditorUi* ui,
    const char* publish_diagnostics_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(
    EditorUi* ui,
    const char* inlay_hints_result_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(
    EditorUi* ui,
    const char* code_lens_result_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(
    EditorUi* ui,
    const char* document_links_result_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(
    EditorUi* ui,
    const char* document_highlights_result_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(
    EditorUi* ui,
    const char* document_symbols_result_json_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(
    EditorUi* ui,
    const char* folding_ranges_result_json_utf8
);
char* editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
    EditorUi* ui,
    const char* workspace_edit_json_utf8,
    const char* document_uri_utf8
);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(EditorUi* ui,
                                                               const uint32_t* data,
                                                               uint32_t data_len);

int32_t editor_core_ui_ffi_editor_ui_set_render_metrics(EditorUi* ui,
                                                       float font_size,
                                                       float line_height_px,
                                                       float cell_width_px,
                                                       float padding_x_px,
                                                       float padding_y_px);
int32_t editor_core_ui_ffi_editor_ui_set_text_vertical_align(EditorUi* ui,
                                                            uint8_t align /* EcuTextVerticalAlign */);
int32_t editor_core_ui_ffi_editor_ui_set_font_families_csv(EditorUi* ui,
                                                           const char* families_utf8);
int32_t editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(EditorUi* ui, uint8_t enabled);
int32_t editor_core_ui_ffi_editor_ui_set_caret_width_px(EditorUi* ui, float width_px);
int32_t editor_core_ui_ffi_editor_ui_set_caret_visible(EditorUi* ui, uint8_t visible);
int32_t editor_core_ui_ffi_editor_ui_set_indent_guides_enabled(EditorUi* ui, uint8_t enabled);
int32_t editor_core_ui_ffi_editor_ui_set_whitespace_render_mode(EditorUi* ui,
                                                               uint8_t mode /* 0=None, 1=Selection, 2=All */);
int32_t editor_core_ui_ffi_editor_ui_set_fold_marker_style(EditorUi* ui,
                                                          uint8_t style /* 0=Hidden, 1=Block, 2=Triangle */);
int32_t editor_core_ui_ffi_editor_ui_set_tab_width(EditorUi* ui, uint32_t width_cells);
int32_t editor_core_ui_ffi_editor_ui_set_tab_key_behavior(
    EditorUi* ui,
    uint8_t behavior /* EcuTabKeyBehavior */
);
int32_t editor_core_ui_ffi_editor_ui_set_auto_pairs_enabled(EditorUi* ui, uint8_t enabled);
int32_t editor_core_ui_ffi_editor_ui_set_bracket_match_highlights_enabled(EditorUi* ui, uint8_t enabled);
int32_t editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(
    EditorUi* ui,
    const char* boundary_chars_utf8
);
int32_t editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_set_gutter_width_cells(EditorUi* ui, uint32_t width_cells);
int32_t editor_core_ui_ffi_editor_ui_get_logical_line_count(EditorUi* ui, uint32_t* out_count);
int32_t editor_core_ui_ffi_editor_ui_get_gutter_width_cells(EditorUi* ui, uint32_t* out_width_cells);
int32_t editor_core_ui_ffi_editor_ui_set_viewport_px(EditorUi* ui,
                                                     uint32_t width_px,
                                                     uint32_t height_px,
                                                     float scale);
void editor_core_ui_ffi_editor_ui_scroll_by_rows(EditorUi* ui, int32_t delta_rows);
void editor_core_ui_ffi_editor_ui_scroll_by_pixels(EditorUi* ui, float delta_y_px);
int32_t editor_core_ui_ffi_editor_ui_get_viewport_state(EditorUi* ui,
                                                        EcuViewportState* out_state);
void editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(EditorUi* ui,
                                                          uint32_t top_visual_row,
                                                          uint32_t sub_row_offset);

int32_t editor_core_ui_ffi_editor_ui_reveal_primary_caret(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_insert_text(EditorUi* ui, const char* text_utf8);
// Execute one editor command encoded as JSON and return command-result JSON.
//
// The returned string is owned by the caller and must be freed with
// `editor_core_ui_ffi_string_free`.
char* editor_core_ui_ffi_editor_ui_execute_command_json(EditorUi* ui,
                                                        const char* command_json_utf8);
// Derived state snapshots as JSON.
//
// The returned strings are owned by the caller and must be freed with
// `editor_core_ui_ffi_string_free`.
char* editor_core_ui_ffi_editor_ui_diagnostics_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_decorations_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_document_symbols_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_folding_regions_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_style_intervals_json(EditorUi* ui,
                                                        uint32_t start,
                                                        uint32_t end);
int32_t editor_core_ui_ffi_editor_ui_insert_tab(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_insert_backtab(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_has_active_snippet_session(EditorUi* ui,
                                                                uint8_t* out_active);
int32_t editor_core_ui_ffi_editor_ui_backspace(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_delete_forward(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_delete_word_back(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_delete_word_forward(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_style(EditorUi* ui,
                                               uint32_t start,
                                               uint32_t end,
                                               uint32_t style_id);
int32_t editor_core_ui_ffi_editor_ui_remove_style(EditorUi* ui,
                                                  uint32_t start,
                                                  uint32_t end,
                                                  uint32_t style_id);
int32_t editor_core_ui_ffi_editor_ui_set_match_highlights(EditorUi* ui,
                                                          const EcuSelectionRange* ranges,
                                                          uint32_t range_count);

// Search helpers (find/replace + match highlights).
//
// `case_sensitive/whole_word/regex` correspond to `editor_core::SearchOptions`.
int32_t editor_core_ui_ffi_editor_ui_search_set_query(EditorUi* ui,
                                                      const char* query_utf8,
                                                      uint8_t case_sensitive,
                                                      uint8_t whole_word,
                                                      uint8_t regex,
                                                      uint32_t* out_match_count);
int32_t editor_core_ui_ffi_editor_ui_search_clear(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_find_next(EditorUi* ui,
                                               const char* query_utf8,
                                               uint8_t case_sensitive,
                                               uint8_t whole_word,
                                               uint8_t regex,
                                               uint8_t* out_found);
int32_t editor_core_ui_ffi_editor_ui_find_prev(EditorUi* ui,
                                               const char* query_utf8,
                                               uint8_t case_sensitive,
                                               uint8_t whole_word,
                                               uint8_t regex,
                                               uint8_t* out_found);
int32_t editor_core_ui_ffi_editor_ui_replace_current(EditorUi* ui,
                                                     const char* query_utf8,
                                                     const char* replacement_utf8,
                                                     uint8_t case_sensitive,
                                                     uint8_t whole_word,
                                                     uint8_t regex,
                                                     uint32_t* out_replaced);
int32_t editor_core_ui_ffi_editor_ui_replace_all(EditorUi* ui,
                                                 const char* query_utf8,
                                                 const char* replacement_utf8,
                                                 uint8_t case_sensitive,
                                                 uint8_t whole_word,
                                                 uint8_t regex,
                                                 uint32_t* out_replaced);
int32_t editor_core_ui_ffi_editor_ui_undo(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_redo(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_visual_by_rows(EditorUi* ui, int32_t delta_rows);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_left(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_right(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_word_left(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_word_right(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_matching_bracket(EditorUi* ui);

// Bookmarks / marks / jump list.
int32_t editor_core_ui_ffi_editor_ui_toggle_bookmark_at_cursor_line(EditorUi* ui,
                                                                   uint8_t* out_added);
int32_t editor_core_ui_ffi_editor_ui_goto_next_bookmark(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_goto_prev_bookmark(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_set_mark_at_cursor(EditorUi* ui, const char* name_utf8);
int32_t editor_core_ui_ffi_editor_ui_goto_mark(EditorUi* ui, const char* name_utf8);
int32_t editor_core_ui_ffi_editor_ui_push_jump_location(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_jump_back(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_jump_forward(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_move_to_visual_line_start(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_visual_line_end(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_document_start(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_document_end(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_visual_by_pages(EditorUi* ui, int32_t delta_pages);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_word_left_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_visual_line_start_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_visual_line_end_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_document_start_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_to_document_end_and_modify_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_visual_by_pages_and_modify_selection(EditorUi* ui,
                                                                              int32_t delta_pages);
int32_t editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection(EditorUi* ui,
                                                                             int32_t delta_rows);

int32_t editor_core_ui_ffi_editor_ui_set_marked_text(EditorUi* ui, const char* text_utf8);
int32_t editor_core_ui_ffi_editor_ui_set_marked_text_ex(EditorUi* ui,
                                                        const char* text_utf8,
                                                        uint32_t selected_start,
                                                        uint32_t selected_len,
                                                        uint32_t replace_start,
                                                        uint32_t replace_len);
void editor_core_ui_ffi_editor_ui_unmark_text(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_commit_text(EditorUi* ui, const char* text_utf8);
int32_t editor_core_ui_ffi_editor_ui_paste_text(EditorUi* ui, const char* text_utf8);

int32_t editor_core_ui_ffi_editor_ui_mouse_down(EditorUi* ui, float x_px, float y_px);
// Extended mouse down with modifier + click-count support.
//
// - `modifiers` bit layout:
//   - bit0: shift
//   - bit1: ctrl
//   - bit2: alt/option
//   - bit3: meta/cmd
// - `click_count`: 1=single, 2=double, 3=triple, 4+=paragraph.
int32_t editor_core_ui_ffi_editor_ui_mouse_down_ex(EditorUi* ui,
                                                  float x_px,
                                                  float y_px,
                                                  uint32_t modifiers,
                                                  uint32_t click_count);
int32_t editor_core_ui_ffi_editor_ui_mouse_dragged(EditorUi* ui, float x_px, float y_px);
void editor_core_ui_ffi_editor_ui_mouse_up(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_render_rgba(EditorUi* ui,
                                                 uint8_t* out_buf,
                                                 uint32_t out_cap,
                                                 uint32_t* out_len);

// Metal / GPU rendering (macOS only).
//
// Notes:
// - The pointers are Objective-C objects passed through as opaque `void*`:
//   - metal_device: `id<MTLDevice>`
//   - metal_command_queue: `id<MTLCommandQueue>`
//   - metal_texture: `id<MTLTexture>` (usually from `CAMetalDrawable.texture`)
// - The host is responsible for presenting the drawable / texture.
int32_t editor_core_ui_ffi_editor_ui_enable_metal(EditorUi* ui,
                                                  void* metal_device,
                                                  void* metal_command_queue);
int32_t editor_core_ui_ffi_editor_ui_render_metal(EditorUi* ui, void* metal_texture);

char* editor_core_ui_ffi_editor_ui_get_text(EditorUi* ui);

// Document modified state (dirty tracking).
int32_t editor_core_ui_ffi_editor_ui_is_modified(EditorUi* ui, uint8_t* out_modified);
int32_t editor_core_ui_ffi_editor_ui_mark_saved(EditorUi* ui);

// Selected text (primary + secondary selections), joined with '\n'.
char* editor_core_ui_ffi_editor_ui_get_selected_text(EditorUi* ui);

// Minimap snapshot as JSON.
char* editor_core_ui_ffi_editor_ui_minimap_json(EditorUi* ui,
                                                uint32_t start_visual_row,
                                                uint32_t count);

int32_t editor_core_ui_ffi_editor_ui_get_selection_offsets(EditorUi* ui,
                                                           uint32_t* out_start,
                                                           uint32_t* out_end);

// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
int32_t editor_core_ui_ffi_editor_ui_delete_selections_only(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_get_selections(EditorUi* ui,
                                                    EcuSelectionRange* out_ranges,
                                                    uint32_t out_cap,
                                                    uint32_t* out_len,
                                                    uint32_t* out_primary_index);

int32_t editor_core_ui_ffi_editor_ui_set_selections(EditorUi* ui,
                                                    const EcuSelectionRange* ranges,
                                                    uint32_t range_count,
                                                    uint32_t primary_index);

int32_t editor_core_ui_ffi_editor_ui_set_rect_selection(EditorUi* ui,
                                                        uint32_t anchor_offset,
                                                        uint32_t active_offset);

int32_t editor_core_ui_ffi_editor_ui_clear_secondary_selections(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_cursor_above(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_cursor_below(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_next_occurrence(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_all_occurrences(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_select_word(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_select_line(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_set_line_selection_offsets(EditorUi* ui,
                                                                uint32_t anchor_offset,
                                                                uint32_t active_offset);
int32_t editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(EditorUi* ui,
                                                                     uint32_t char_offset);
int32_t editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets(EditorUi* ui,
                                                                     uint32_t anchor_offset,
                                                                     uint32_t active_offset);
int32_t editor_core_ui_ffi_editor_ui_expand_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_expand_selection_by(EditorUi* ui,
                                                         uint32_t unit,
                                                         uint32_t count,
                                                         uint32_t direction);
int32_t editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(EditorUi* ui,
                                                              uint32_t char_offset,
                                                              uint8_t make_primary);

int32_t editor_core_ui_ffi_editor_ui_get_marked_range(EditorUi* ui,
                                                      uint8_t* out_has_marked,
                                                      uint32_t* out_start,
                                                      uint32_t* out_len);

int32_t editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(EditorUi* ui,
                                                                     uint32_t char_offset,
                                                                     uint32_t* out_line,
                                                                     uint32_t* out_column);

int32_t editor_core_ui_ffi_editor_ui_char_offset_to_view_point(EditorUi* ui,
                                                               uint32_t char_offset,
                                                               float* out_x,
                                                               float* out_y,
                                                               float* out_line_height_px);

int32_t editor_core_ui_ffi_editor_ui_view_point_to_char_offset(EditorUi* ui,
                                                               float x_px,
                                                               float y_px,
                                                               uint32_t* out_char_offset);

// Hit-test a view point and return an LSP `DocumentLink` JSON payload (if present).
//
// - On success, returns `ECU_OK` and sets:
//   - `out_has_link = 1` and `out_json_utf8` to a newly allocated string (caller frees via
//     `editor_core_ui_ffi_string_free`), or
//   - `out_has_link = 0` and `out_json_utf8 = NULL` when there is no link at the point.
int32_t editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
    EditorUi* ui,
    float x_px,
    float y_px,
    uint8_t* out_has_link,
    char** out_json_utf8
);

// Hit-test a view point and return an LSP `InlayHint` JSON payload (if present).
//
// - On success, returns `ECU_OK` and sets:
//   - `out_has_hint = 1` and `out_json_utf8` to a newly allocated string (caller frees via
//     `editor_core_ui_ffi_string_free`), or
//   - `out_has_hint = 0` and `out_json_utf8 = NULL` when there is no inlay hint at the point.
int32_t editor_core_ui_ffi_editor_ui_get_inlay_hint_json_at_view_point(
    EditorUi* ui,
    float x_px,
    float y_px,
    uint8_t* out_has_hint,
    char** out_json_utf8
);

// Hit-test a view point and return an LSP `CodeLens` JSON payload (if present).
//
// - On success, returns `ECU_OK` and sets:
//   - `out_has_lens = 1` and `out_json_utf8` to a newly allocated string (caller frees via
//     `editor_core_ui_ffi_string_free`), or
//   - `out_has_lens = 0` and `out_json_utf8 = NULL` when there is no code lens at the point.
int32_t editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(
    EditorUi* ui,
    float x_px,
    float y_px,
    uint8_t* out_has_lens,
    char** out_json_utf8
);

#ifdef __cplusplus
} // extern "C"
#endif
