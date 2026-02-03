# editor-core-sublime

`editor-core-sublime` 为 `editor-core` 提供轻量级的 `.sublime-syntax` **语法高亮 + 折叠**引擎。

它专为无头/编辑器内核使用而设计:生成样式区间和折叠区域,可应用到 `EditorStateManager` 而无需任何特定 UI。

## 特性

- 加载和编译基于 Sublime Text YAML 的 `.sublime-syntax` 定义。
- 支持用于高亮和折叠的常见 Sublime 特性:
  - 上下文、包含、元作用域
  - 通过 `extends` 实现基本继承
  - 多行上下文折叠
- 将文档高亮为:
  - 样式区间(`Interval`,基于字符偏移量)
  - 折叠区域(`FoldRegion`,基于逻辑行范围)
- 通过 `SublimeScopeMapper` 在 Sublime 作用域和编辑器 `StyleId` 之间建立稳定映射。
- `SublimeProcessor` 实现 `editor_core::processing::DocumentProcessor` 并发出 `ProcessingEdit` 更新(`StyleLayerId::SUBLIME_SYNTAX` + 折叠编辑)。

## 设计概览

此 crate 保持输出格式与 `editor-core` 对齐:

- 所有区间偏移量都是**字符偏移量**(而非字节偏移量)。
- 高亮生成"派生状态"补丁(`ProcessingEdit`),由宿主应用到编辑器状态管理器。
- 折叠区域可以选择在重新高亮过程中保留用户折叠状态。

低级引擎通过 `highlight_document` 暴露,高级集成通过 `SublimeProcessor` 暴露。

## 快速开始

### 添加依赖

```toml
[dependencies]
editor-core = "0.1"
editor-core-sublime = "0.1"
```

### 高亮并应用派生状态

```rust
use editor_core::EditorStateManager;
use editor_core::processing::DocumentProcessor;
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};

let mut state = EditorStateManager::new("fn main() {}\n", 80);

// 加载语法(从 YAML、文件或通过搜索路径从引用)。
let mut set = SublimeSyntaxSet::new();
let syntax = set.load_from_str(r#"
%YAML 1.2
---
name: Minimal Rust
scope: source.rust
contexts:
  main:
    - match: '\\b(fn|let)\\b'
      scope: keyword.control.rust
"#).unwrap();

let mut processor = SublimeProcessor::new(syntax, set);

let edits = processor.process(&state).unwrap();
state.apply_processing_edits(edits);

// 使用 `state.get_viewport_content_styled(...)` 进行渲染。
```

## 注意事项

- `.sublime-syntax` 是一个大型格式;此 crate 专注于实用无头高亮/折叠所需的子集。
- 使用 `SublimeScopeMapper` 将 `StyleId` 值映射回作用域以进行主题化。
