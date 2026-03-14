//! `tauri-editor`
//!
//! 一个以 **Tauri v2 + WebView (HTML/CSS/JS)** 为目标的 `editor-core` 前端实现（text-grid / 非富文本）。
//!
//! 目前该 crate 提供：
//! - 从 `editor_core::ComposedGrid` 生成 Web 友好的 `ViewportSnapshot`（runs 压缩 + style-set interning）
//! - 计算 composed-rows（doc rows + above-line 虚拟行）所需的 `ComposedRowIndex`
//! - 一个纯 Rust 的 `EditorBackend`（便于 Tauri 命令层复用与单元测试）

mod backend;
pub mod composed_row_index;
pub mod render_model;
pub mod snapshot;

pub use backend::{EditorBackend, EditorBackendError, EditorKey, KeyModifiers};
