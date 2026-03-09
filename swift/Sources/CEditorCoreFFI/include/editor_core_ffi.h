#pragma once

// 说明：
// SwiftPM 的 C target 会把 `include/` 作为 public header 的入口。
// 我们不在 Swift 包内复制 Rust 侧生成/维护的头文件，而是直接包含仓库里的真实头文件，
// 避免 ABI 演进时出现 Swift 侧头文件不同步的问题。
//
// 该路径以本文件所在目录为基准：
// swift/Sources/CEditorCoreFFI/include/editor_core_ffi.h
#include "../../../../crates/editor-core-ffi/include/editor_core_ffi.h"

