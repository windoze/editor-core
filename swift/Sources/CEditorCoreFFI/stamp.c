#include "editor_core_ffi.h"

// 与 `CEditorCoreUIFFI/stamp.c` 同理：用于在 ABI 变更时触发 SwiftPM 重建/重新链接 Rust staticlib。
int editor_core_ffi_swiftpm_api_revision(void) {
    return 3;
}
