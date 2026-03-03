#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle.
typedef struct EditorUi EditorUi;

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

typedef struct EcuSelectionRange {
  uint32_t start;
  uint32_t end;
} EcuSelectionRange;

// Return codes (int32).
// 0 = OK
// 1 = invalid argument
// 4 = buffer too small (out_len contains required size)
// 7 = internal error (check last_error_message)

void editor_core_ui_ffi_string_free(char* ptr);
char* editor_core_ui_ffi_last_error_message(void);
char* editor_core_ui_ffi_version(void);

EditorUi* editor_core_ui_ffi_editor_ui_new(const char* initial_text_utf8,
                                          uint32_t viewport_width_cells);
void editor_core_ui_ffi_editor_ui_free(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_set_theme(EditorUi* ui, const EcuTheme* theme);
int32_t editor_core_ui_ffi_editor_ui_set_style_colors(EditorUi* ui,
                                                      const EcuStyleColors* styles,
                                                      uint32_t style_count);

// Sublime syntax integration (highlighting + folding).
int32_t editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(EditorUi* ui, const char* yaml_utf8);
int32_t editor_core_ui_ffi_editor_ui_sublime_set_syntax_path(EditorUi* ui, const char* path_utf8);
void editor_core_ui_ffi_editor_ui_sublime_disable(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(EditorUi* ui,
                                                                const char* scope_utf8,
                                                                uint32_t* out_style_id);
char* editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(EditorUi* ui, uint32_t style_id);

// Tree-sitter integration (highlighting + folding).
int32_t editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries(
    EditorUi* ui,
    const char* highlights_query_utf8,
    const char* folds_query_utf8 // nullable
);
void editor_core_ui_ffi_editor_ui_treesitter_disable(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(EditorUi* ui,
                                                                     const char* capture_utf8,
                                                                     uint32_t* out_style_id);
char* editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(EditorUi* ui, uint32_t style_id);

// LSP-derived state ingestion (diagnostics + semantic tokens).
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(
    EditorUi* ui,
    const char* publish_diagnostics_json_utf8
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
int32_t editor_core_ui_ffi_editor_ui_set_gutter_width_cells(EditorUi* ui, uint32_t width_cells);
int32_t editor_core_ui_ffi_editor_ui_set_viewport_px(EditorUi* ui,
                                                     uint32_t width_px,
                                                     uint32_t height_px,
                                                     float scale);
void editor_core_ui_ffi_editor_ui_scroll_by_rows(EditorUi* ui, int32_t delta_rows);

int32_t editor_core_ui_ffi_editor_ui_insert_text(EditorUi* ui, const char* text_utf8);
int32_t editor_core_ui_ffi_editor_ui_backspace(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_delete_forward(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_style(EditorUi* ui,
                                               uint32_t start,
                                               uint32_t end,
                                               uint32_t style_id);
int32_t editor_core_ui_ffi_editor_ui_remove_style(EditorUi* ui,
                                                  uint32_t start,
                                                  uint32_t end,
                                                  uint32_t style_id);
int32_t editor_core_ui_ffi_editor_ui_undo(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_redo(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_visual_by_rows(EditorUi* ui, int32_t delta_rows);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_left(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_move_grapheme_right(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_set_marked_text(EditorUi* ui, const char* text_utf8);
void editor_core_ui_ffi_editor_ui_unmark_text(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_commit_text(EditorUi* ui, const char* text_utf8);

int32_t editor_core_ui_ffi_editor_ui_mouse_down(EditorUi* ui, float x_px, float y_px);
int32_t editor_core_ui_ffi_editor_ui_mouse_dragged(EditorUi* ui, float x_px, float y_px);
void editor_core_ui_ffi_editor_ui_mouse_up(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_render_rgba(EditorUi* ui,
                                                 uint8_t* out_buf,
                                                 uint32_t out_cap,
                                                 uint32_t* out_len);

char* editor_core_ui_ffi_editor_ui_get_text(EditorUi* ui);

int32_t editor_core_ui_ffi_editor_ui_get_selection_offsets(EditorUi* ui,
                                                           uint32_t* out_start,
                                                           uint32_t* out_end);

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
int32_t editor_core_ui_ffi_editor_ui_expand_selection(EditorUi* ui);
int32_t editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(EditorUi* ui,
                                                              uint32_t char_offset,
                                                              uint8_t make_primary);

int32_t editor_core_ui_ffi_editor_ui_get_marked_range(EditorUi* ui,
                                                      uint8_t* out_has_marked,
                                                      uint32_t* out_start,
                                                      uint32_t* out_len);

int32_t editor_core_ui_ffi_editor_ui_char_offset_to_view_point(EditorUi* ui,
                                                               uint32_t char_offset,
                                                               float* out_x,
                                                               float* out_y,
                                                               float* out_line_height_px);

int32_t editor_core_ui_ffi_editor_ui_view_point_to_char_offset(EditorUi* ui,
                                                               float x_px,
                                                               float y_px,
                                                               uint32_t* out_char_offset);

#ifdef __cplusplus
} // extern "C"
#endif
