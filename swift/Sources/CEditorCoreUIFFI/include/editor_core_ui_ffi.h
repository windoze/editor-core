#pragma once

// SwiftPM C target 的 public header 入口。
// 直接包含 Rust 侧真实头文件，避免复制导致不同步。
//
// 该路径以本文件所在目录为基准：
// swift/Sources/CEditorCoreUIFFI/include/editor_core_ui_ffi.h
#include "../../../../crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h"

