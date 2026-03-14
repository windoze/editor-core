const invoke = (() => {
  const tauri = window.__TAURI__;
  if (!tauri || !tauri.core || !tauri.core.invoke) {
    const msg =
      "Tauri 全局对象不可用：请确认 tauri.conf.json 里 app.withGlobalTauri=true，并使用 Tauri WebView 运行。";
    console.error(msg, { tauri });
    throw new Error(msg);
  }
  return tauri.core.invoke;
})();

const scrollViewport = document.getElementById("scrollViewport");
const spacerTop = document.getElementById("spacerTop");
const spacerBottom = document.getElementById("spacerBottom");
const rowsLayer = document.getElementById("rowsLayer");
const selectionsLayer = document.getElementById("selections");
const cursorEl = document.getElementById("cursor");
const imeInput = document.getElementById("imeInput");
const minimapEl = document.getElementById("minimap");
const minimapCanvas = document.getElementById("minimapCanvas");
const minimapViewportEl = document.getElementById("minimapViewport");
const scrollbarEl = document.getElementById("scrollbar");
const scrollbarThumbEl = document.getElementById("scrollbarThumb");

let invokeQueue = Promise.resolve();
function invokeQueued(cmd, args = {}) {
  const run = () => invoke(cmd, args);
  invokeQueue = invokeQueue.then(run, run);
  return invokeQueue;
}

const state = {
  cellWidthPx: 8,
  lineHeightPx: 20,
  widthCells: 80,
  heightRows: 30,
  gutterWidthPx: 0,
  logicalLineCount: 1,
  overscan: 30,
  rendering: false,
  pending: false,
  totalRows: 0,
  minimapTotalRows: 0,
  minimapBucketSize: 1,
  minimapSamples: [],
  minimapLastFetchedAt: 0,
  minimapLastHeight: 0,
  minimapLastWidthCells: 0,
  lastPasteAt: 0,
  compositionActive: false,
  compositionPendingText: "",
  compositionFlushScheduled: false,
  beforeinputSupported: false,
  ignoreNextInsertTextAt: 0,
  ignoreNextInsertTextText: "",
  ignoreNextInputAt: 0,
  ignoreNextInputText: "",
  renderedStartRow: null,
  renderedCount: 0,
  renderedWidthCells: 0,
  lineKeys: new Map(),
  perfLastLogAt: 0,
  lastInputAt: 0,
  lastInputKind: "",
  lastDomStats: null,
};

function measure() {
  const style = getComputedStyle(scrollViewport);
  const lineHeightPx = Number.parseFloat(style.lineHeight);
  state.lineHeightPx = Number.isFinite(lineHeightPx) ? lineHeightPx : 20;

  // 用 `ch` 单位测量更稳定（`1ch` 定义为当前字体里 “0” 的 advance width）。
  // 将 probe 放在 scrollViewport 内，确保继承相同的 font 相关样式（包含可能的缩放/覆盖）。
  const probe = document.createElement("div");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.width = "100ch";
  probe.style.height = "0";
  probe.style.overflow = "hidden";
  scrollViewport.appendChild(probe);
  const rect = probe.getBoundingClientRect();
  probe.remove();

  const cw = rect.width / 100;
  state.cellWidthPx = Number.isFinite(cw) && cw > 0 ? cw : 8;

  updateGutterWidth();
}

function gutterCellsForLineCount(lineCount) {
  const digits = String(Math.max(1, lineCount)).length;
  // [fold icon 1 cell] + [space 1] + [digits] + [space 1]
  return Math.max(4, 1 + 1 + digits + 1);
}

function updateGutterWidth() {
  const gutterCells = gutterCellsForLineCount(state.logicalLineCount);
  state.gutterWidthPx = gutterCells * state.cellWidthPx;
  document.documentElement.style.setProperty("--gutter-width", `${state.gutterWidthPx}px`);
}

async function syncViewport() {
  const wpx = scrollViewport.clientWidth;
  const hpx = scrollViewport.clientHeight;
  const contentWpx = Math.max(0, wpx - state.gutterWidthPx);
  const nextWidthCells = Math.max(1, Math.floor(contentWpx / state.cellWidthPx));
  const nextHeightRows = Math.max(1, Math.floor(hpx / state.lineHeightPx));

  if (nextWidthCells === state.widthCells && nextHeightRows === state.heightRows) {
    return;
  }

  state.widthCells = nextWidthCells;
  state.heightRows = nextHeightRows;

  await invokeQueued("set_viewport", {
    widthCells: state.widthCells,
    heightRows: state.heightRows,
  });
}

function clamp(n, lo, hi) {
  return Math.min(Math.max(n, lo), hi);
}

function ensureRowVisible(row, marginRows = 2) {
  const marginPx = Math.max(0, marginRows) * state.lineHeightPx;
  const viewportTop = scrollViewport.scrollTop;
  const viewportBottom = viewportTop + scrollViewport.clientHeight;

  const rowTop = row * state.lineHeightPx;
  const rowBottom = rowTop + state.lineHeightPx;

  if (rowTop < viewportTop + marginPx) {
    scrollViewport.scrollTop = Math.max(0, rowTop - marginPx);
    return;
  }

  if (rowBottom > viewportBottom - marginPx) {
    const nextTop = rowBottom + marginPx - scrollViewport.clientHeight;
    scrollViewport.scrollTop = Math.max(0, nextTop);
  }
}

function updateScrollbarUI() {
  const trackH = scrollbarEl.clientHeight;
  if (!trackH) return;

  const viewportH = scrollViewport.clientHeight;
  const totalRows = state.totalRows || 0;
  const totalH = totalRows * state.lineHeightPx;

  if (totalH <= 0 || viewportH <= 0) {
    scrollbarThumbEl.style.height = "0px";
    scrollbarThumbEl.style.transform = "translateY(0px)";
    return;
  }

  if (totalH <= viewportH) {
    scrollbarThumbEl.style.height = `${trackH}px`;
    scrollbarThumbEl.style.transform = "translateY(0px)";
    return;
  }

  const minThumbH = 24;
  const thumbH = clamp((viewportH / totalH) * trackH, minThumbH, trackH);
  const maxScrollTop = Math.max(0, totalH - viewportH);
  const maxThumbTop = Math.max(0, trackH - thumbH);
  const top = maxScrollTop > 0 ? (scrollViewport.scrollTop / maxScrollTop) * maxThumbTop : 0;

  scrollbarThumbEl.style.height = `${thumbH}px`;
  scrollbarThumbEl.style.transform = `translateY(${top}px)`;
}

function updateMinimapViewportUI() {
  const docTotal = state.minimapTotalRows || 0;
  const h = minimapEl.clientHeight;
  if (!docTotal || !h) {
    minimapViewportEl.style.transform = "translateY(-9999px)";
    return;
  }

  // minimap 当前基于 doc visual rows；scrollViewport 以 composed rows 为准。
  // 首版先按“doc≈composed”做近似；未来引入大量 above-line rows 时再做精确映射。
  const visibleStart = Math.floor(scrollViewport.scrollTop / state.lineHeightPx);
  const visibleCount = state.heightRows;

  const rawTop = (visibleStart / docTotal) * h;
  const rawH = Math.max(16, (visibleCount / docTotal) * h);
  const top = clamp(rawTop, 0, Math.max(0, h - rawH));

  minimapViewportEl.style.height = `${rawH}px`;
  minimapViewportEl.style.transform = `translateY(${top}px)`;
}

let minimapRefreshInFlight = false;
async function refreshMinimap() {
  if (minimapRefreshInFlight) return;
  minimapRefreshInFlight = true;
  try {
    const height = Math.max(1, minimapEl.clientHeight);
    const snap = await invokeQueued("get_minimap", { height });
    state.minimapTotalRows = snap.totalRows || 0;
    state.minimapBucketSize = snap.bucketSize || 1;
    state.minimapSamples = Array.isArray(snap.samples) ? snap.samples : [];
    state.minimapLastFetchedAt = performance.now();
    state.minimapLastHeight = height;
    state.minimapLastWidthCells = state.widthCells;

    drawMinimap();
    updateMinimapViewportUI();
  } finally {
    minimapRefreshInFlight = false;
  }
}

function drawMinimap() {
  const cssW = minimapEl.clientWidth;
  const cssH = minimapEl.clientHeight;
  if (!cssW || !cssH) return;

  const dpr = window.devicePixelRatio || 1;
  const w = Math.max(1, Math.floor(cssW * dpr));
  const h = Math.max(1, Math.floor(cssH * dpr));

  if (minimapCanvas.width !== w || minimapCanvas.height !== h) {
    minimapCanvas.width = w;
    minimapCanvas.height = h;
  }

  const ctx = minimapCanvas.getContext("2d");
  if (!ctx) return;
  ctx.clearRect(0, 0, w, h);

  const samples = state.minimapSamples || [];
  if (!samples.length) return;

  // samples 期望长度≈CSS 高度；如果不一致，按比例映射。
  for (let y = 0; y < cssH; y++) {
    const idx = Math.floor((y / cssH) * samples.length);
    const v = samples[idx] ?? 0;
    if (!v) continue;
    const alpha = Math.min(0.9, Math.max(0, v / 255));
    ctx.fillStyle = `rgba(215, 218, 224, ${alpha * 0.75})`;
    ctx.fillRect(0, Math.floor(y * dpr), w, Math.ceil(dpr));
  }
}

function maybeRefreshMinimap(snapshot) {
  const now = performance.now();
  const height = minimapEl.clientHeight;
  const needsSize = height !== state.minimapLastHeight;
  const needsWrap = snapshot && snapshot.widthCells !== state.minimapLastWidthCells;
  const needsFirst = !state.minimapTotalRows;
  const needsAfterInput =
    state.lastInputAt > 0 &&
    state.lastInputAt > state.minimapLastFetchedAt &&
    now - state.minimapLastFetchedAt > 300;

  if (needsSize || needsWrap || needsFirst || needsAfterInput) {
    void refreshMinimap();
  }
}

function computeRequestRange(totalRowsHint = null) {
  const visibleStart = Math.floor(scrollViewport.scrollTop / state.lineHeightPx);
  const start = Math.max(0, visibleStart - state.overscan);
  let count = state.heightRows + state.overscan * 2;
  if (totalRowsHint != null) {
    const maxCount = Math.max(0, totalRowsHint - start);
    count = Math.min(count, maxCount);
  }
  return { start, count };
}

function classForStyleSet(styleSetId, styleSets) {
  const styleIds = styleSets[styleSetId] || [];
  let cls = "run";

  // 内置 style id（来自 editor-core/src/intervals.rs）。
  const FOLD_PLACEHOLDER_STYLE_ID = 0x03000001;
  if (styleIds.includes(FOLD_PLACEHOLDER_STYLE_ID)) {
    cls += " style-fold-placeholder";
  }

  const IME_MARKED_TEXT_STYLE_ID = 0x07000001;
  if (styleIds.includes(IME_MARKED_TEXT_STYLE_ID)) {
    cls += " style-ime-marked";
  }

  // editor-core-highlight-simple（JSON/INI 等）
  const SIMPLE_STYLE_STRING = 0x02000001;
  const SIMPLE_STYLE_NUMBER = 0x02000002;
  const SIMPLE_STYLE_BOOLEAN = 0x02000003;
  const SIMPLE_STYLE_NULL = 0x02000004;
  const SIMPLE_STYLE_SECTION = 0x02000010;
  const SIMPLE_STYLE_KEY = 0x02000011;
  const SIMPLE_STYLE_COMMENT = 0x02000012;

  if (styleIds.includes(SIMPLE_STYLE_STRING)) cls += " style-syntax-string";
  if (styleIds.includes(SIMPLE_STYLE_NUMBER)) cls += " style-syntax-number";
  if (styleIds.includes(SIMPLE_STYLE_BOOLEAN)) cls += " style-syntax-boolean";
  if (styleIds.includes(SIMPLE_STYLE_NULL)) cls += " style-syntax-null";
  if (styleIds.includes(SIMPLE_STYLE_SECTION)) cls += " style-syntax-section";
  if (styleIds.includes(SIMPLE_STYLE_KEY)) cls += " style-syntax-key";
  if (styleIds.includes(SIMPLE_STYLE_COMMENT)) cls += " style-syntax-comment";

  // tauri-editor 自定义（Markdown MVP）
  const MD_STYLE_HEADING = 0x02000101;
  const MD_STYLE_INLINE_CODE = 0x02000102;
  const MD_STYLE_LINK = 0x02000103;

  if (styleIds.includes(MD_STYLE_HEADING)) cls += " style-md-heading";
  if (styleIds.includes(MD_STYLE_INLINE_CODE)) cls += " style-md-inline-code";
  if (styleIds.includes(MD_STYLE_LINK)) cls += " style-md-link";

  // Tree-sitter（tauri-editor 内置映射；StyleId 由后端选择并写入 style layer：TREE_SITTER）
  const TS_STYLE_COMMENT = 0x06000001;
  const TS_STYLE_COMMENT_DOC = 0x06000002;
  const TS_STYLE_STRING = 0x06000003;
  const TS_STYLE_ESCAPE = 0x06000004;
  const TS_STYLE_KEYWORD = 0x06000005;
  const TS_STYLE_OPERATOR = 0x06000006;
  const TS_STYLE_PUNCT = 0x06000007;
  const TS_STYLE_TYPE = 0x06000008;
  const TS_STYLE_TYPE_BUILTIN = 0x06000009;
  const TS_STYLE_FUNCTION = 0x0600000a;
  const TS_STYLE_FUNCTION_MACRO = 0x0600000b;
  const TS_STYLE_VARIABLE_PARAMETER = 0x0600000c;
  const TS_STYLE_VARIABLE_BUILTIN = 0x0600000d;
  const TS_STYLE_CONSTANT = 0x0600000e;
  const TS_STYLE_CONSTANT_BUILTIN = 0x0600000f;
  const TS_STYLE_ATTRIBUTE = 0x06000010;
  const TS_STYLE_LABEL = 0x06000011;
  const TS_STYLE_CONSTRUCTOR = 0x06000012;
  const TS_STYLE_PROPERTY = 0x06000013;

  if (styleIds.includes(TS_STYLE_COMMENT)) cls += " style-ts-comment";
  if (styleIds.includes(TS_STYLE_COMMENT_DOC)) cls += " style-ts-comment-doc";
  if (styleIds.includes(TS_STYLE_STRING)) cls += " style-ts-string";
  if (styleIds.includes(TS_STYLE_ESCAPE)) cls += " style-ts-escape";
  if (styleIds.includes(TS_STYLE_KEYWORD)) cls += " style-ts-keyword";
  if (styleIds.includes(TS_STYLE_OPERATOR)) cls += " style-ts-operator";
  if (styleIds.includes(TS_STYLE_PUNCT)) cls += " style-ts-punct";
  if (styleIds.includes(TS_STYLE_TYPE)) cls += " style-ts-type";
  if (styleIds.includes(TS_STYLE_TYPE_BUILTIN)) cls += " style-ts-type-builtin";
  if (styleIds.includes(TS_STYLE_FUNCTION)) cls += " style-ts-function";
  if (styleIds.includes(TS_STYLE_FUNCTION_MACRO)) cls += " style-ts-macro";
  if (styleIds.includes(TS_STYLE_VARIABLE_PARAMETER)) cls += " style-ts-variable-parameter";
  if (styleIds.includes(TS_STYLE_VARIABLE_BUILTIN)) cls += " style-ts-variable-builtin";
  if (styleIds.includes(TS_STYLE_CONSTANT)) cls += " style-ts-constant";
  if (styleIds.includes(TS_STYLE_CONSTANT_BUILTIN)) cls += " style-ts-constant-builtin";
  if (styleIds.includes(TS_STYLE_ATTRIBUTE)) cls += " style-ts-attribute";
  if (styleIds.includes(TS_STYLE_LABEL)) cls += " style-ts-label";
  if (styleIds.includes(TS_STYLE_CONSTRUCTOR)) cls += " style-ts-constructor";
  if (styleIds.includes(TS_STYLE_PROPERTY)) cls += " style-ts-property";

  // LSP diagnostics underline（0x0400_0100 | severity_bits）
  const DIAG_BASE = 0x04000100;
  for (const id of styleIds) {
    if ((id & 0xffffff00) === DIAG_BASE) {
      const sev = id & 0xff;
      if (sev === 1) cls += " style-lsp-diag-error";
      if (sev === 2) cls += " style-lsp-diag-warning";
      if (sev === 3) cls += " style-lsp-diag-info";
      if (sev === 4) cls += " style-lsp-diag-hint";
    }
  }

  // LSP semantic tokens（StyleId 编码：高 16 位=canonical token type，低 16 位=modifier bits）
  const LSP_TOKEN_TYPES = [
    "namespace",
    "type",
    "class",
    "enum",
    "interface",
    "struct",
    "typeParameter",
    "parameter",
    "variable",
    "property",
    "enumMember",
    "event",
    "function",
    "method",
    "macro",
    "keyword",
    "modifier",
    "comment",
    "string",
    "number",
    "regexp",
    "operator",
  ];
  for (const id of styleIds) {
    // 该 demo 自定义 style ids 都在 0x0200_0000 以上；因此把小范围的 id 视为 LSP semantic。
    if (id <= 0 || id >= 0x02000000) continue;
    const typeIdx = id >>> 16;
    const name = LSP_TOKEN_TYPES[typeIdx];
    if (name) cls += ` style-lsp-${name}`;
    const mods = id & 0xffff;
    const MOD_DOCUMENTATION = 1 << 8;
    if (mods & MOD_DOCUMENTATION) cls += " style-lsp-mod-doc";
  }

  // editor-core 内置 decoration style id（intervals.rs）
  const INLAY_HINT_STYLE_ID = 0x08000001;
  const CODE_LENS_STYLE_ID = 0x08000002;
  const DOCUMENT_LINK_STYLE_ID = 0x08000003;

  if (styleIds.includes(INLAY_HINT_STYLE_ID)) cls += " style-inlay-hint";
  if (styleIds.includes(CODE_LENS_STYLE_ID)) cls += " style-code-lens";
  if (styleIds.includes(DOCUMENT_LINK_STYLE_ID)) cls += " style-document-link";

  return cls;
}

function lineKey(line, styleSets) {
  // 关键：不能只用 `styleSetId` 当 key，因为 style-set interning 是“每次快照重新编号”的，
  // viewport 切片不同会导致相同 styles 对应不同的 id。这里直接用 styles 列表做稳定 key。
  let key = `${line.kind}:${line.logicalLine ?? ""}:${line.visualInLogical ?? ""}`;
  if (line.fold) {
    key += `:f${line.fold.endLine}:${line.fold.collapsed ? 1 : 0}`;
  } else {
    key += ":f";
  }
  for (const run of line.runs) {
    const [styleSetId, sourceKind, sourceOffset, cells, text] = run;
    const styleIds = styleSets[styleSetId] || [];
    key += `|${styleIds.join(",")}:${sourceKind}:${sourceOffset}:${cells}:${text}`;
  }
  return key;
}

function formatLineNumber(line) {
  if (line.kind !== 0) return "";
  if (line.logicalLine == null) return "";
  const visualInLogical = line.visualInLogical ?? 0;
  if (visualInLogical !== 0) return "";
  return String(line.logicalLine + 1);
}

function updateRowElement(rowEl, line, styleSets) {
  rowEl.dataset.row = String(line.row);
  if (line.logicalLine != null) {
    rowEl.dataset.logicalLine = String(line.logicalLine);
  } else {
    delete rowEl.dataset.logicalLine;
  }

  const gutterEl = document.createElement("div");
  gutterEl.className = "gutter-cell";

  const foldEl = document.createElement("span");
  foldEl.className = "fold-toggle";
  if (line.kind === 0 && line.visualInLogical === 0 && line.logicalLine != null && line.fold) {
    foldEl.classList.add("foldable");
    foldEl.textContent = line.fold.collapsed ? "▶" : "▼";
    foldEl.dataset.action = "toggleFold";
    foldEl.dataset.logicalLine = String(line.logicalLine);
    foldEl.dataset.endLine = String(line.fold.endLine);
    foldEl.dataset.collapsed = line.fold.collapsed ? "1" : "0";
  } else {
    foldEl.textContent = "";
  }

  const numEl = document.createElement("span");
  numEl.className = "line-number";
  numEl.textContent = formatLineNumber(line);

  gutterEl.appendChild(foldEl);
  gutterEl.appendChild(numEl);

  const lineEl = document.createElement("div");
  lineEl.className = "line";

  const frag = document.createDocumentFragment();
  for (const run of line.runs) {
    const [styleSetId, _sourceKind, _sourceOffset, cells, text] = run;
    const span = document.createElement("span");
    span.className = classForStyleSet(styleSetId, styleSets);
    span.textContent = text;
    // 按 cells 强制分配宽度，避免 CJK/emoji/font fallback 破坏 2-cell 假设导致 caret 落进 glyph 中间。
    if (cells > 0) {
      span.style.width = `${cells * state.cellWidthPx}px`;
    }
    frag.appendChild(span);
  }
  lineEl.replaceChildren(frag);

  rowEl.replaceChildren(gutterEl, lineEl);
}

function createLineElement(line, styleSets) {
  const rowEl = document.createElement("div");
  rowEl.className = "row";
  updateRowElement(rowEl, line, styleSets);
  return rowEl;
}

function renderSnapshot(snapshot) {
  const t0 = performance.now();

  // 同步 tab-size（确保 `\t` 展开与内核一致）。
  document.documentElement.style.setProperty("--tab-size", String(snapshot.tabWidth));

  const startRow = snapshot.startRow;
  const totalRows = snapshot.totalRows;
  state.totalRows = totalRows;

  const topPx = startRow * state.lineHeightPx;
  const bottomRows = Math.max(0, totalRows - (startRow + snapshot.lines.length));
  const bottomPx = bottomRows * state.lineHeightPx;

  spacerTop.style.height = `${topPx}px`;
  spacerBottom.style.height = `${bottomPx}px`;

  let createdLines = 0;
  let removedLines = 0;
  let updatedLines = 0;

  const newCount = snapshot.lines.length;
  const oldStart = state.renderedStartRow;
  const oldCount = state.renderedCount;
  const newStart = snapshot.startRow;

  const hasOverlap =
    oldStart != null &&
    oldCount > 0 &&
    Math.max(oldStart, newStart) < Math.min(oldStart + oldCount, newStart + newCount);

  const canPatch = hasOverlap && state.renderedWidthCells === snapshot.widthCells;

  if (!canPatch) {
    state.lineKeys.clear();
    const frag = document.createDocumentFragment();
    for (const line of snapshot.lines) {
      frag.appendChild(createLineElement(line, snapshot.styleSets));
      state.lineKeys.set(line.row, lineKey(line, snapshot.styleSets));
      createdLines++;
    }
    rowsLayer.replaceChildren(frag);
    state.renderedStartRow = newStart;
    state.renderedCount = newCount;
    state.renderedWidthCells = snapshot.widthCells;
    const domMs = performance.now() - t0;
    return {
      domMs,
      createdLines,
      removedLines,
      updatedLines: createdLines,
      totalLines: newCount,
      fullRender: true,
    };
  }

  const delta = newStart - oldStart;
  if (delta > 0) {
    for (let i = 0; i < delta && rowsLayer.firstChild; i++) {
      const row = Number(rowsLayer.firstChild.dataset.row);
      state.lineKeys.delete(row);
      rowsLayer.removeChild(rowsLayer.firstChild);
      removedLines++;
    }
  } else if (delta < 0) {
    const insertCount = Math.min(-delta, newCount);
    for (let i = insertCount - 1; i >= 0; i--) {
      const line = snapshot.lines[i];
      rowsLayer.insertBefore(createLineElement(line, snapshot.styleSets), rowsLayer.firstChild);
      state.lineKeys.set(line.row, lineKey(line, snapshot.styleSets));
      createdLines++;
    }
  }

  while (rowsLayer.children.length > newCount) {
    const last = rowsLayer.lastChild;
    if (!last) break;
    const row = Number(last.dataset.row);
    state.lineKeys.delete(row);
    rowsLayer.removeChild(last);
    removedLines++;
  }

  while (rowsLayer.children.length < newCount) {
    const idx = rowsLayer.children.length;
    const line = snapshot.lines[idx];
    rowsLayer.appendChild(createLineElement(line, snapshot.styleSets));
    state.lineKeys.set(line.row, lineKey(line, snapshot.styleSets));
    createdLines++;
  }

  // 更新内容：只重建发生变化的行（行级 diff）。
  let mismatch = false;
  for (let i = 0; i < newCount; i++) {
    const line = snapshot.lines[i];
    const el = rowsLayer.children[i];
    if (!el || Number(el.dataset.row) !== line.row) {
      mismatch = true;
      break;
    }

    const key = lineKey(line, snapshot.styleSets);
    if (state.lineKeys.get(line.row) !== key) {
      updateLineElement(el, line, snapshot.styleSets);
      state.lineKeys.set(line.row, key);
      updatedLines++;
    }
  }

  if (mismatch) {
    // 防御式回退：如果某次 patch 因为意外原因导致 row 对不上，直接全量重建。
    state.lineKeys.clear();
    const frag = document.createDocumentFragment();
    for (const line of snapshot.lines) {
      frag.appendChild(createLineElement(line, snapshot.styleSets));
      state.lineKeys.set(line.row, lineKey(line, snapshot.styleSets));
      createdLines++;
    }
    rowsLayer.replaceChildren(frag);
    updatedLines = createdLines;
    removedLines = 0;
  }

  state.renderedStartRow = newStart;
  state.renderedCount = newCount;
  state.renderedWidthCells = snapshot.widthCells;

  const domMs = performance.now() - t0;
  return { domMs, createdLines, removedLines, updatedLines, totalLines: newCount, fullRender: false };
}

function positionCursor(cursor) {
  const [row, xCells] = cursor;
  const xPx = state.gutterWidthPx + xCells * state.cellWidthPx - scrollViewport.scrollLeft;
  const yPx = row * state.lineHeightPx - scrollViewport.scrollTop;

  cursorEl.style.transform = `translate(${xPx}px, ${yPx}px)`;

  // 让系统 IME 候选窗靠近 caret（暂时只做定位，IME 状态机后续补齐）。
  imeInput.style.transform = `translate(${xPx}px, ${yPx}px)`;
}

function renderSelection(selection, snapshot) {
  if (!selection) {
    selectionsLayer.replaceChildren();
    return;
  }

  const [[aRow, aX], [bRow, bX]] = selection;
  let startRow = aRow;
  let startX = aX;
  let endRow = bRow;
  let endX = bX;

  if (endRow < startRow || (endRow === startRow && endX < startX)) {
    startRow = bRow;
    startX = bX;
    endRow = aRow;
    endX = aX;
  }

  const visibleStart = snapshot.startRow;
  const visibleEnd = snapshot.startRow + snapshot.lines.length; // exclusive

  const firstRow = Math.max(startRow, visibleStart);
  const lastRow = Math.min(endRow, visibleEnd - 1);
  if (firstRow > lastRow) {
    selectionsLayer.replaceChildren();
    return;
  }

  const widthCells = snapshot.widthCells;
  const frag = document.createDocumentFragment();

  for (let row = firstRow; row <= lastRow; row++) {
    let left = 0;
    let width = widthCells;
    if (row === startRow && row === endRow) {
      left = Math.min(startX, endX);
      width = Math.max(0, Math.abs(endX - startX));
    } else if (row === startRow) {
      left = startX;
      width = Math.max(0, widthCells - startX);
    } else if (row === endRow) {
      left = 0;
      width = Math.max(0, endX);
    }

    if (width <= 0) continue;

    const el = document.createElement("div");
    el.className = "selection-rect";
    const xPx = state.gutterWidthPx + left * state.cellWidthPx - scrollViewport.scrollLeft;
    const yPx = row * state.lineHeightPx - scrollViewport.scrollTop;
    el.style.width = `${width * state.cellWidthPx}px`;
    el.style.transform = `translate(${xPx}px, ${yPx}px)`;
    frag.appendChild(el);
  }

  selectionsLayer.replaceChildren(frag);
}

async function renderOnce() {
  if (state.rendering) {
    state.pending = true;
    return;
  }
  state.rendering = true;
  const tFrameStart = performance.now();
  try {
    await syncViewport();

    let { start, count } = computeRequestRange(state.totalRows || null);
    let frame = await invokeQueued("get_frame", { startRow: start, count });
    let snapshot = frame.snapshot;

    // 依据后端返回的 logicalLineCount 计算 gutter 宽度；如果 gutter 变化导致 viewport 宽度变化，
    // 需要再 set_viewport 一次并重取一帧，否则 wrap/cells 会有一帧不一致。
    const prevGutterWidthPx = state.gutterWidthPx;
    const prevWidthCells = state.widthCells;
    if (
      snapshot.logicalLineCount != null &&
      snapshot.logicalLineCount !== state.logicalLineCount
    ) {
      state.logicalLineCount = snapshot.logicalLineCount;
      updateGutterWidth();
    }

    if (state.gutterWidthPx !== prevGutterWidthPx) {
      await syncViewport();
      if (state.widthCells !== prevWidthCells) {
        ({ start, count } = computeRequestRange(snapshot.totalRows || null));
        frame = await invokeQueued("get_frame", { startRow: start, count });
        snapshot = frame.snapshot;
      }
    }
    const domStats = renderSnapshot(snapshot);

    positionCursor(frame.cursor);
    renderSelection(frame.selection, snapshot);
    updateScrollbarUI();
    updateMinimapViewportUI();
    maybeRefreshMinimap(snapshot);

    state.lastDomStats = domStats;
    const tFrameEnd = performance.now();
    if (tFrameEnd - state.perfLastLogAt > 1000) {
      const inputLatency =
        state.lastInputAt > 0 ? Math.max(0, tFrameEnd - state.lastInputAt) : null;
      const inputStr =
        inputLatency == null ? "n/a" : `${state.lastInputKind} ${inputLatency.toFixed(1)}ms`;
      console.debug(
        `[perf] frame=${(tFrameEnd - tFrameStart).toFixed(1)}ms dom=${domStats.domMs.toFixed(
          1,
        )}ms lines(u=${domStats.updatedLines}/${domStats.totalLines}, c=${domStats.createdLines}, r=${
          domStats.removedLines
        }) input=${inputStr}`,
      );
      state.perfLastLogAt = tFrameEnd;
    }
  } finally {
    state.rendering = false;
    if (state.pending) {
      state.pending = false;
      queueMicrotask(() => {
        void renderOnce();
      });
    }
  }
}

function scheduleRender() {
  if (state.pending) return;
  state.pending = true;
  requestAnimationFrame(() => {
    state.pending = false;
    void renderOnce();
  });
}

function ensureFocus() {
  if (document.activeElement !== imeInput) {
    // `preventScroll` 选项在部分 WebView（尤其是旧版 WKWebView）上可能不支持，会抛异常，
    // 从而导致后续输入/快捷键完全失效。这里做兼容降级。
    try {
      imeInput.focus({ preventScroll: true });
    } catch {
      imeInput.focus();
    }
  }
}

let dragSelecting = false;
let dragAnchor = null; // { row, xCells }
let dragLatestClient = null; // { x, y }
let dragFlushScheduled = false;
let dragClearAfterFlush = false;
let dragLastSent = null; // { row, xCells }

function hitTestFromClientPoint(clientX, clientY) {
  const rect = scrollViewport.getBoundingClientRect();
  const x = clientX - rect.left + scrollViewport.scrollLeft;
  const y = clientY - rect.top + scrollViewport.scrollTop;
  const xInContent = x - state.gutterWidthPx;

  const row = clamp(
    Math.floor((y + state.lineHeightPx / 2) / state.lineHeightPx),
    0,
    Math.max(0, state.totalRows - 1),
  );
  const xCells = clamp(
    Math.floor((Math.max(0, xInContent) + state.cellWidthPx / 2) / state.cellWidthPx),
    0,
    Math.max(0, state.widthCells),
  );

  return { row, xCells, rect };
}

function maybeAutoScrollOnDrag(clientY, rect) {
  const edgePx = Math.min(24, Math.max(8, state.lineHeightPx * 0.75));
  const yInViewport = clientY - rect.top;
  if (yInViewport < edgePx) {
    scrollViewport.scrollTop = Math.max(0, scrollViewport.scrollTop - state.lineHeightPx);
  } else if (yInViewport > rect.height - edgePx) {
    scrollViewport.scrollTop = Math.max(0, scrollViewport.scrollTop + state.lineHeightPx);
  }
}

function scheduleDragFlush() {
  if (dragFlushScheduled) return;
  dragFlushScheduled = true;
  requestAnimationFrame(() => {
    dragFlushScheduled = false;

    const anchor = dragAnchor;
    const latest = dragLatestClient;
    if (!anchor || !latest) {
      if (dragClearAfterFlush) {
        dragClearAfterFlush = false;
        dragAnchor = null;
        dragLatestClient = null;
        dragLastSent = null;
      }
      return;
    }

    // 拖拽时靠近上下边缘自动滚动（尽量不做复杂的像素级速度曲线，先保证可用）。
    const rect = scrollViewport.getBoundingClientRect();
    if (dragSelecting) {
      maybeAutoScrollOnDrag(latest.y, rect);
    }

    const hit = hitTestFromClientPoint(latest.x, latest.y);
    if (dragLastSent && dragLastSent.row === hit.row && dragLastSent.xCells === hit.xCells) {
      if (dragClearAfterFlush) {
        dragClearAfterFlush = false;
        dragAnchor = null;
        dragLatestClient = null;
        dragLastSent = null;
      }
      return;
    }
    dragLastSent = { row: hit.row, xCells: hit.xCells };

    state.lastInputAt = performance.now();
    state.lastInputKind = "mouseDrag";
    void invokeQueued("mouse_drag", {
      anchorRow: anchor.row,
      anchorXCells: anchor.xCells,
      row: hit.row,
      xCells: hit.xCells,
    }).then(scheduleRender);

    if (dragClearAfterFlush) {
      dragClearAfterFlush = false;
      dragAnchor = null;
      dragLatestClient = null;
      dragLastSent = null;
    }
  });
}

function stopDragSelecting(clientX, clientY) {
  if (!dragSelecting) return;
  dragSelecting = false;
  dragLatestClient = { x: clientX, y: clientY };
  dragClearAfterFlush = true;
  scheduleDragFlush();
  window.removeEventListener("mousemove", onDragMove);
  window.removeEventListener("mouseup", onDragEnd);
  window.removeEventListener("blur", onDragBlur);
}

function onDragMove(e) {
  if (!dragSelecting) return;
  if ((e.buttons & 1) === 0) {
    stopDragSelecting(e.clientX, e.clientY);
    return;
  }
  dragLatestClient = { x: e.clientX, y: e.clientY };
  scheduleDragFlush();
}

function onDragEnd(e) {
  stopDragSelecting(e.clientX, e.clientY);
}

function onDragBlur() {
  // blur 时不知道最后的鼠标位置；用 viewport 顶部作为保守收口。
  const rect = scrollViewport.getBoundingClientRect();
  stopDragSelecting(rect.left, rect.top);
}

scrollViewport.addEventListener(
  "scroll",
  () => {
    updateScrollbarUI();
    updateMinimapViewportUI();
    scheduleRender();
  },
  { passive: true },
);
window.addEventListener("resize", () => {
  measure();
  scheduleRender();
});
window.addEventListener("focus", ensureFocus);
rowsLayer.addEventListener("mousedown", (e) => {
  const target = e.target;
  if (!(target instanceof HTMLElement)) return;
  if (e.button !== 0) return;
  if (target.dataset.action !== "toggleFold") return;

  e.preventDefault();
  e.stopPropagation();
  ensureFocus();

  const startLine = Number(target.dataset.logicalLine);
  const endLine = Number(target.dataset.endLine);
  const collapsed = target.dataset.collapsed === "1";
  if (!Number.isFinite(startLine) || !Number.isFinite(endLine)) return;

  state.lastInputAt = performance.now();
  state.lastInputKind = "toggleFold";
  void invokeQueued("toggle_fold", {
    startLine,
    endLine,
    collapsed,
  }).then(scheduleRender);
});

let scrollbarDragging = false;
let scrollbarDragStartY = 0;
let scrollbarDragStartThumbTop = 0;

function onScrollbarDragMove(e) {
  if (!scrollbarDragging) return;
  const trackRect = scrollbarEl.getBoundingClientRect();
  const thumbRect = scrollbarThumbEl.getBoundingClientRect();
  const thumbH = thumbRect.height;
  const maxThumbTop = Math.max(0, trackRect.height - thumbH);
  if (maxThumbTop <= 0) return;

  const dy = e.clientY - scrollbarDragStartY;
  const nextThumbTop = clamp(scrollbarDragStartThumbTop + dy, 0, maxThumbTop);

  const totalH = state.totalRows * state.lineHeightPx;
  const viewportH = scrollViewport.clientHeight;
  const maxScrollTop = Math.max(0, totalH - viewportH);
  const nextScrollTop = maxScrollTop > 0 ? (nextThumbTop / maxThumbTop) * maxScrollTop : 0;
  scrollViewport.scrollTop = nextScrollTop;
}

function stopScrollbarDrag() {
  if (!scrollbarDragging) return;
  scrollbarDragging = false;
  window.removeEventListener("mousemove", onScrollbarDragMove);
  window.removeEventListener("mouseup", stopScrollbarDrag);
}

scrollbarThumbEl.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  ensureFocus();
  updateScrollbarUI();

  scrollbarDragging = true;
  const trackRect = scrollbarEl.getBoundingClientRect();
  const thumbRect = scrollbarThumbEl.getBoundingClientRect();
  scrollbarDragStartY = e.clientY;
  scrollbarDragStartThumbTop = thumbRect.top - trackRect.top;
  window.addEventListener("mousemove", onScrollbarDragMove, { passive: true });
  window.addEventListener("mouseup", stopScrollbarDrag, { passive: true });
});

scrollbarEl.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  if (e.target === scrollbarThumbEl) return;
  e.preventDefault();
  ensureFocus();
  updateScrollbarUI();

  const trackRect = scrollbarEl.getBoundingClientRect();
  const thumbRect = scrollbarThumbEl.getBoundingClientRect();
  const thumbH = thumbRect.height;
  const maxThumbTop = Math.max(0, trackRect.height - thumbH);
  if (maxThumbTop <= 0) return;

  const clickY = e.clientY - trackRect.top;
  const nextThumbTop = clamp(clickY - thumbH / 2, 0, maxThumbTop);

  const totalH = state.totalRows * state.lineHeightPx;
  const viewportH = scrollViewport.clientHeight;
  const maxScrollTop = Math.max(0, totalH - viewportH);
  const nextScrollTop = maxScrollTop > 0 ? (nextThumbTop / maxThumbTop) * maxScrollTop : 0;
  scrollViewport.scrollTop = nextScrollTop;
});

let minimapDragging = false;

function setScrollFromMinimapClientY(clientY) {
  const rect = minimapEl.getBoundingClientRect();
  const y = clamp(clientY - rect.top, 0, rect.height);
  const frac = rect.height > 0 ? y / rect.height : 0;
  const docTotal = state.minimapTotalRows || 0;
  if (!docTotal) return;

  const targetRow = frac * docTotal;
  const topRow = Math.max(0, targetRow - state.heightRows / 2);
  scrollViewport.scrollTop = topRow * state.lineHeightPx;
}

function onMinimapDragMove(e) {
  if (!minimapDragging) return;
  setScrollFromMinimapClientY(e.clientY);
}

function stopMinimapDrag(e) {
  if (!minimapDragging) return;
  minimapDragging = false;
  window.removeEventListener("mousemove", onMinimapDragMove);
  window.removeEventListener("mouseup", stopMinimapDrag);
  if (e && typeof e.clientY === "number") {
    setScrollFromMinimapClientY(e.clientY);
  }
}

minimapEl.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  ensureFocus();
  minimapDragging = true;
  setScrollFromMinimapClientY(e.clientY);
  window.addEventListener("mousemove", onMinimapDragMove, { passive: true });
  window.addEventListener("mouseup", stopMinimapDrag, { passive: true });
});
scrollViewport.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  // Shift+点击已支持：走后端 selecting=true 的扩选逻辑；暂不启用 Shift+拖拽（避免锚点语义混乱）。
  if (e.shiftKey) {
    ensureFocus();
    const hit = hitTestFromClientPoint(e.clientX, e.clientY);
    state.lastInputAt = performance.now();
    state.lastInputKind = "mouseDownShift";
    void invokeQueued("mouse_down", {
      row: hit.row,
      xCells: hit.xCells,
      modifiers: {
        shift: true,
        ctrl: e.ctrlKey,
        alt: e.altKey,
        meta: e.metaKey,
      },
    }).then(scheduleRender);
    return;
  }

  ensureFocus();
  e.preventDefault();

  const hit = hitTestFromClientPoint(e.clientX, e.clientY);

  dragSelecting = true;
  dragAnchor = { row: hit.row, xCells: hit.xCells };
  dragLatestClient = { x: e.clientX, y: e.clientY };
  dragLastSent = { row: hit.row, xCells: hit.xCells };
  dragClearAfterFlush = false;
  window.addEventListener("mousemove", onDragMove, { passive: true });
  window.addEventListener("mouseup", onDragEnd, { passive: true });
  window.addEventListener("blur", onDragBlur, { passive: true });

  state.lastInputAt = performance.now();
  state.lastInputKind = "mouseDown";
  void invokeQueued("mouse_down", {
    row: hit.row,
    xCells: hit.xCells,
    modifiers: {
      shift: false,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey,
    },
  }).then(scheduleRender);
});

imeInput.addEventListener("beforeinput", (e) => {
  state.beforeinputSupported = true;

  // composition 期间的输入由 `composition*` 管线接管；这里处理非 IME 的普通输入。
  if (e.isComposing) return;

  const type = e.inputType;
  const data = e.data ?? "";

  if (type === "insertText") {
    const now = performance.now();
    if (
      state.ignoreNextInsertTextText &&
      now - state.ignoreNextInsertTextAt < 100 &&
      data === state.ignoreNextInsertTextText
    ) {
      // 一些 WebView 会在 `compositionend` 之后再补发一次 `beforeinput(insertText)`；
      // 我们以 composition 管线为准，避免重复插入。
      e.preventDefault();
      state.ignoreNextInsertTextText = "";
      state.ignoreNextInsertTextAt = 0;
      if (imeInput.value) imeInput.value = "";
      return;
    }

    if (!data) return;
    e.preventDefault();
    state.lastInputAt = performance.now();
    state.lastInputKind = "insertText";
    void invokeQueued("insert_text", { text: data }).then(scheduleRender);
  } else if (type === "insertLineBreak" || type === "insertParagraph") {
    e.preventDefault();
    state.lastInputAt = performance.now();
    state.lastInputKind = type;
    void invokeQueued("insert_newline", { autoIndent: true }).then(scheduleRender);
  } else if (type === "insertTab") {
    e.preventDefault();
    state.lastInputAt = performance.now();
    state.lastInputKind = type;
    void invokeQueued("insert_tab").then(scheduleRender);
  } else if (type === "deleteContentBackward") {
    e.preventDefault();
    state.lastInputAt = performance.now();
    state.lastInputKind = type;
    void invokeQueued("backspace").then(scheduleRender);
  } else if (type === "deleteContentForward") {
    e.preventDefault();
    state.lastInputAt = performance.now();
    state.lastInputKind = type;
    void invokeQueued("delete_forward").then(scheduleRender);
  } else if (type === "insertFromPaste") {
    e.preventDefault();
    // 避免 keydown + beforeinput 双触发导致重复粘贴。
    const now = performance.now();
    if (now - state.lastPasteAt > 30) {
      state.lastPasteAt = now;
      state.lastInputAt = now;
      state.lastInputKind = type;
      void invokeQueued("paste").then(scheduleRender);
    }
  }

  if (e.defaultPrevented) {
    imeInput.value = "";
  }
});

imeInput.addEventListener("input", (e) => {
  if (e.isComposing) return;

  const value = imeInput.value ?? "";
  if (!value) return;

  // beforeinput 可用时，input 事件通常不应该驱动编辑（我们会 preventDefault 并自行发送命令）。
  // 但在不支持 beforeinput 的 WebView 上，这里会是主要输入通路（比如普通打字/右键粘贴）。
  if (!state.beforeinputSupported) {
    const now = performance.now();
    if (
      state.ignoreNextInputText &&
      now - state.ignoreNextInputAt < 120 &&
      value === state.ignoreNextInputText
    ) {
      // 类似 beforeinput 的去重：避免 compositionend 后的“补发 input”导致重复插入。
      state.ignoreNextInputText = "";
      state.ignoreNextInputAt = 0;
      imeInput.value = "";
      return;
    }

    // 避免 keydown(paste) + input 双触发导致重复粘贴。
    if (now - state.lastPasteAt < 80) {
      imeInput.value = "";
      return;
    }

    state.lastInputAt = now;
    state.lastInputKind = "inputFallback";
    void invokeQueued("insert_text", { text: value }).then(scheduleRender);
  }

  imeInput.value = "";
});

function scheduleCompositionFlush() {
  if (state.compositionFlushScheduled) return;
  state.compositionFlushScheduled = true;
  requestAnimationFrame(() => {
    state.compositionFlushScheduled = false;
    if (!state.compositionActive) return;
    const text = state.compositionPendingText;
    state.lastInputAt = performance.now();
    state.lastInputKind = "compositionUpdate";
    void invokeQueued("composition_update", { text }).then(scheduleRender);
  });
}

imeInput.addEventListener("compositionstart", () => {
  state.compositionActive = true;
  state.compositionPendingText = "";
  state.compositionFlushScheduled = false;
  state.lastInputAt = performance.now();
  state.lastInputKind = "compositionStart";
  void invokeQueued("composition_start").then(scheduleRender);
});

imeInput.addEventListener("compositionupdate", (e) => {
  state.compositionPendingText = e.data ?? "";
  scheduleCompositionFlush();
});

imeInput.addEventListener("compositionend", (e) => {
  const text = e.data ?? "";
  state.compositionActive = false;
  state.compositionPendingText = "";
  state.compositionFlushScheduled = false;
  // 见 `beforeinput(insertText)` 的去重逻辑：避免重复 commit。
  state.ignoreNextInsertTextAt = performance.now();
  state.ignoreNextInsertTextText = text;
  // 某些 WebView 不触发 beforeinput，但会触发 input；这里同样做去重。
  state.ignoreNextInputAt = state.ignoreNextInsertTextAt;
  state.ignoreNextInputText = text;
  state.lastInputAt = performance.now();
  state.lastInputKind = "compositionEnd";
  void invokeQueued("composition_end", { text }).then(scheduleRender);
  imeInput.value = "";
});

document.addEventListener("keydown", async (e) => {
  // 绝大多数输入事件（beforeinput/input/composition*）都依赖隐藏 textarea 获取焦点；
  // 这里尽量保证任何键盘交互都能把焦点拉回来，避免“看起来完全不能输入”的状态。
  ensureFocus();

  const isMac = navigator.platform.toLowerCase().includes("mac");
  const ctrlOrCmd = isMac ? e.metaKey : e.ctrlKey;

  if (ctrlOrCmd) {
    const k = e.key.toLowerCase();
    if (k === "a") {
      e.preventDefault();
      ensureFocus();
      state.lastInputAt = performance.now();
      state.lastInputKind = "selectAll";
      await invokeQueued("select_all");
      scheduleRender();
      return;
    }
    if (k === "c") {
      e.preventDefault();
      ensureFocus();
      state.lastInputAt = performance.now();
      state.lastInputKind = "copy";
      await invokeQueued("copy");
      return;
    }
    if (k === "x") {
      e.preventDefault();
      ensureFocus();
      state.lastInputAt = performance.now();
      state.lastInputKind = "cut";
      await invokeQueued("cut");
      scheduleRender();
      return;
    }
    if (k === "v") {
      e.preventDefault();
      ensureFocus();
      state.lastPasteAt = performance.now();
      state.lastInputAt = state.lastPasteAt;
      state.lastInputKind = "paste";
      await invokeQueued("paste");
      scheduleRender();
      return;
    }
    if (k === "z") {
      e.preventDefault();
      ensureFocus();
      if (e.shiftKey) {
        state.lastInputAt = performance.now();
        state.lastInputKind = "redo";
        await invokeQueued("redo");
      } else {
        state.lastInputAt = performance.now();
        state.lastInputKind = "undo";
        await invokeQueued("undo");
      }
      scheduleRender();
      return;
    }
    if (k === "y") {
      e.preventDefault();
      ensureFocus();
      state.lastInputAt = performance.now();
      state.lastInputKind = "redo";
      await invokeQueued("redo");
      scheduleRender();
      return;
    }
  }

  // 部分 WebView 不支持 `beforeinput`（尤其是 delete/insertLineBreak 等 inputType），
  // 我们用 keydown 兜底处理编辑按键，避免编辑完全失效。
  if (!state.beforeinputSupported) {
    if (e.key === "Backspace") {
      e.preventDefault();
      state.lastInputAt = performance.now();
      state.lastInputKind = "keydownBackspace";
      await invokeQueued("backspace");
      scheduleRender();
      return;
    }
    if (e.key === "Delete") {
      e.preventDefault();
      state.lastInputAt = performance.now();
      state.lastInputKind = "keydownDelete";
      await invokeQueued("delete_forward");
      scheduleRender();
      return;
    }
    if (e.key === "Enter") {
      e.preventDefault();
      state.lastInputAt = performance.now();
      state.lastInputKind = "keydownEnter";
      await invokeQueued("insert_newline", { autoIndent: true });
      scheduleRender();
      return;
    }
    if (e.key === "Tab") {
      e.preventDefault();
      state.lastInputAt = performance.now();
      state.lastInputKind = "keydownTab";
      await invokeQueued("insert_tab");
      scheduleRender();
      return;
    }
  }

  const keyMap = {
    ArrowLeft: "arrowLeft",
    ArrowRight: "arrowRight",
    ArrowUp: "arrowUp",
    ArrowDown: "arrowDown",
    Home: "home",
    End: "end",
    PageUp: "pageUp",
    PageDown: "pageDown",
  };

  const mapped = keyMap[e.key];
  if (!mapped) return;

  e.preventDefault();
  ensureFocus();

  await invokeQueued("key_down", {
    key: mapped,
    modifiers: {
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey,
    },
  });

  // 键盘导航应尽量把 caret 保持在 viewport 内（selection 扩展同理：active end=cursor）。
  const cursor = await invokeQueued("get_cursor");
  if (Array.isArray(cursor) && cursor.length >= 2) {
    ensureRowVisible(cursor[0]);
  }

  scheduleRender();
});

const ro = new ResizeObserver(() => {
  measure();
  scheduleRender();
});
ro.observe(scrollViewport);

(async () => {
  try {
    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }
  } catch {
    // ignore
  }

  measure();
  ensureFocus();
  await renderOnce();
})();
