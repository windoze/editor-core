#include "editor_core_ui_ffi.h"

// SwiftPM 的 C target 若只有 headers，依赖图很容易“错过”仓库根目录 Rust staticlib 的更新，
// 进而静默链接到旧的 `.a`，导致新增符号缺失（例如新增一个 `extern "C"` API）。
//
// 这个文件的唯一目的：给 `CEditorCoreUIFFI` 提供一个本地编译单元，便于在 ABI 变更时通过
// bump revision 触发 SwiftPM 重新执行 build plugin + 重新链接。
//
// 规则：每当 `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h` 的导出符号发生变化时，
// 递增该值。
int editor_core_ui_ffi_swiftpm_api_revision(void) {
    return 5;
}
