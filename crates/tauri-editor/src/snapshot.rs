use serde::{Deserialize, Serialize};

/// `RunSnapshot` 中的来源类型：来自文档文本（可映射到 `char` offset）。
pub const SOURCE_KIND_DOCUMENT: u8 = 0;
/// `RunSnapshot` 中的来源类型：来自虚拟文本（inlay/code lens/折行缩进等）。
pub const SOURCE_KIND_VIRTUAL: u8 = 1;

/// `LineSnapshot.kind`：文档内容行（wrap+fold 后的 doc visual row）。
pub const LINE_KIND_DOCUMENT: u8 = 0;
/// `LineSnapshot.kind`：插入在某个 logical line 上方的虚拟行（code lens / view zone）。
pub const LINE_KIND_VIRTUAL_ABOVE_LINE: u8 = 1;

/// Web 友好的 viewport 快照（composed rows 空间）。
///
/// 设计目标：
/// - 避免把 `editor_core::ComposedGrid` 直接 serde 成 JSON（层级深、重复字段多）
/// - 用 runs（按样式段压缩）表达每一行，减少 JS 侧的 DOM 节点与解析开销
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ViewportSnapshot {
    /// 本次返回的第一行（绝对 composed row）。
    pub start_row: u32,
    /// composed rows 总行数（用于 scrollHeight/spacer 计算）。
    pub total_rows: u32,
    /// viewport 宽度（cells）。
    pub width_cells: u32,
    /// tab 宽度（cells），用于前端 `tab-size` 与 hit-test 对齐。
    pub tab_width: u16,
    /// 行快照（每个元素对应一个 composed row）。
    pub lines: Vec<LineSnapshot>,
    /// style-set interning 表：`style_sets[style_set_id] = [styleId, ...]`。
    pub style_sets: Vec<Vec<u32>>,
}

/// 单行快照（composed visual row）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LineSnapshot {
    /// 该行的绝对 composed row（调试/定位用）。
    pub row: u32,
    /// 行类型：`LINE_KIND_*` 常量。
    pub kind: u8,
    /// runs：按连续样式段压缩后的 spans。
    pub runs: Vec<RunSnapshot>,
}

/// 一个样式段 run（tuple 形式，减少 JSON 对象开销）。
///
/// 字段语义：
/// - `0: style_set_id`：样式集合 intern id
/// - `1: source_kind`：0=Document，1=Virtual
/// - `2: source_offset`：Document=起始 `char` offset；Virtual=anchor `char` offset
/// - `3: text`：该段文本
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct RunSnapshot(pub (u32, u8, u32, String));

impl RunSnapshot {
    pub fn new(style_set_id: u32, source_kind: u8, source_offset: u32, text: String) -> Self {
        Self((style_set_id, source_kind, source_offset, text))
    }

    pub fn style_set_id(&self) -> u32 {
        self.0.0
    }

    pub fn source_kind(&self) -> u8 {
        self.0.1
    }

    pub fn source_offset(&self) -> u32 {
        self.0.2
    }

    pub fn text(&self) -> &str {
        &self.0.3
    }
}
