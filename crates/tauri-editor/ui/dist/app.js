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
const cursorEl = document.getElementById("cursor");
const imeInput = document.getElementById("imeInput");

const state = {
  cellWidthPx: 8,
  lineHeightPx: 20,
  widthCells: 80,
  heightRows: 30,
  overscan: 30,
  rendering: false,
  pending: false,
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

  await invoke("set_viewport", {
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

  return cls;
}

function renderSnapshot(snapshot) {
  // 同步 tab-size（确保 `\t` 展开与内核一致）。
  document.documentElement.style.setProperty("--tab-size", String(snapshot.tabWidth));

  const startRow = snapshot.startRow;
  const totalRows = snapshot.totalRows;

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

async function renderOnce() {
  if (state.rendering) {
    state.pending = true;
    return;
  }
  state.rendering = true;
  try {
    await syncViewport();

    const { start, count } = computeRequestRange();
    const snapshot = await invoke("get_viewport", { startRow: start, count });
    renderSnapshot(snapshot);

    const cursor = await invoke("get_cursor");
    positionCursor(cursor);
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
scrollViewport.addEventListener("mousedown", ensureFocus);

document.addEventListener("keydown", async (e) => {
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

  await invoke("key_down", {
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
