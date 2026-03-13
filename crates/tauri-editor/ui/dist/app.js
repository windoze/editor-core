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
const linesLayer = document.getElementById("linesLayer");
const selectionsLayer = document.getElementById("selections");
const cursorEl = document.getElementById("cursor");
const imeInput = document.getElementById("imeInput");

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
  overscan: 30,
  rendering: false,
  pending: false,
  totalRows: 0,
  lastPasteAt: 0,
  compositionActive: false,
  compositionPendingText: "",
  compositionFlushScheduled: false,
  ignoreNextInsertTextAt: 0,
  ignoreNextInsertTextText: "",
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
}

async function syncViewport() {
  const wpx = scrollViewport.clientWidth;
  const hpx = scrollViewport.clientHeight;
  const nextWidthCells = Math.max(1, Math.floor(wpx / state.cellWidthPx));
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

  return cls;
}

function renderSnapshot(snapshot) {
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

  const frag = document.createDocumentFragment();
  for (const line of snapshot.lines) {
    const lineEl = document.createElement("div");
    lineEl.className = "line";
    lineEl.dataset.row = String(line.row);

    for (const run of line.runs) {
      const [styleSetId, _sourceKind, _sourceOffset, cells, text] = run;
      const span = document.createElement("span");
      span.className = classForStyleSet(styleSetId, snapshot.styleSets);
      span.textContent = text;
      // 按 cells 强制分配宽度，避免 CJK/emoji/font fallback 破坏 2-cell 假设导致 caret 落进 glyph 中间。
      if (cells > 0) {
        span.style.width = `${cells * state.cellWidthPx}px`;
      }
      lineEl.appendChild(span);
    }

    frag.appendChild(lineEl);
  }

  linesLayer.replaceChildren(frag);
}

function positionCursor(cursor) {
  const [row, xCells] = cursor;
  const xPx = xCells * state.cellWidthPx - scrollViewport.scrollLeft;
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
    const xPx = left * state.cellWidthPx - scrollViewport.scrollLeft;
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
  try {
    await syncViewport();

    const { start, count } = computeRequestRange();
    const snapshot = await invokeQueued("get_viewport", { startRow: start, count });
    renderSnapshot(snapshot);

    const cursor = await invokeQueued("get_cursor");
    positionCursor(cursor);

    const selection = await invokeQueued("get_selection");
    renderSelection(selection, snapshot);
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
    imeInput.focus({ preventScroll: true });
  }
}

scrollViewport.addEventListener("scroll", scheduleRender, { passive: true });
window.addEventListener("resize", () => {
  measure();
  scheduleRender();
});
window.addEventListener("focus", ensureFocus);
scrollViewport.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  ensureFocus();

  const rect = scrollViewport.getBoundingClientRect();
  const x = e.clientX - rect.left + scrollViewport.scrollLeft;
  const y = e.clientY - rect.top + scrollViewport.scrollTop;

  const row = clamp(
    Math.floor((y + state.lineHeightPx / 2) / state.lineHeightPx),
    0,
    Math.max(0, state.totalRows - 1),
  );
  const xCells = clamp(
    Math.floor((x + state.cellWidthPx / 2) / state.cellWidthPx),
    0,
    Math.max(0, state.widthCells),
  );

  void invokeQueued("mouse_down", {
    row,
    xCells,
    modifiers: {
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey,
    },
  }).then(scheduleRender);
});

imeInput.addEventListener("beforeinput", (e) => {
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
    void invokeQueued("insert_text", { text: data }).then(scheduleRender);
  } else if (type === "insertLineBreak" || type === "insertParagraph") {
    e.preventDefault();
    void invokeQueued("insert_newline", { autoIndent: true }).then(scheduleRender);
  } else if (type === "insertTab") {
    e.preventDefault();
    void invokeQueued("insert_tab").then(scheduleRender);
  } else if (type === "deleteContentBackward") {
    e.preventDefault();
    void invokeQueued("backspace").then(scheduleRender);
  } else if (type === "deleteContentForward") {
    e.preventDefault();
    void invokeQueued("delete_forward").then(scheduleRender);
  } else if (type === "insertFromPaste") {
    e.preventDefault();
    // 避免 keydown + beforeinput 双触发导致重复粘贴。
    const now = performance.now();
    if (now - state.lastPasteAt > 30) {
      state.lastPasteAt = now;
      void invokeQueued("paste").then(scheduleRender);
    }
  }

  if (e.defaultPrevented) {
    imeInput.value = "";
  }
});

imeInput.addEventListener("input", (e) => {
  // 在我们 `preventDefault()` 的路径上通常不会触发；这里做兜底，避免隐藏 textarea 堆积内容。
  if (e.isComposing) return;
  if (imeInput.value) imeInput.value = "";
});

function scheduleCompositionFlush() {
  if (state.compositionFlushScheduled) return;
  state.compositionFlushScheduled = true;
  requestAnimationFrame(() => {
    state.compositionFlushScheduled = false;
    if (!state.compositionActive) return;
    const text = state.compositionPendingText;
    void invokeQueued("composition_update", { text }).then(scheduleRender);
  });
}

imeInput.addEventListener("compositionstart", () => {
  state.compositionActive = true;
  state.compositionPendingText = "";
  state.compositionFlushScheduled = false;
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
  void invokeQueued("composition_end", { text }).then(scheduleRender);
  imeInput.value = "";
});

document.addEventListener("keydown", async (e) => {
  const isMac = navigator.platform.toLowerCase().includes("mac");
  const ctrlOrCmd = isMac ? e.metaKey : e.ctrlKey;

  if (ctrlOrCmd) {
    const k = e.key.toLowerCase();
    if (k === "a") {
      e.preventDefault();
      ensureFocus();
      await invokeQueued("select_all");
      scheduleRender();
      return;
    }
    if (k === "c") {
      e.preventDefault();
      ensureFocus();
      await invokeQueued("copy");
      return;
    }
    if (k === "x") {
      e.preventDefault();
      ensureFocus();
      await invokeQueued("cut");
      scheduleRender();
      return;
    }
    if (k === "v") {
      e.preventDefault();
      ensureFocus();
      state.lastPasteAt = performance.now();
      await invokeQueued("paste");
      scheduleRender();
      return;
    }
    if (k === "z") {
      e.preventDefault();
      ensureFocus();
      if (e.shiftKey) {
        await invokeQueued("redo");
      } else {
        await invokeQueued("undo");
      }
      scheduleRender();
      return;
    }
    if (k === "y") {
      e.preventDefault();
      ensureFocus();
      await invokeQueued("redo");
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
