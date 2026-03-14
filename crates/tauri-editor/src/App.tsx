import { useEffect } from "react";

export default function App() {
  useEffect(() => {
    // React 18 StrictMode 在 dev 下会 double-invoke effects。我们的编辑器初始化是“命令式 + 全局监听器”，
    // 因此这里加一个全局 guard，避免在 dev/HMR 下重复挂载导致交互异常。
    const g = globalThis as unknown as {
      __TAURI_EDITOR_BOOTSTRAPPED__?: boolean;
    };
    if (g.__TAURI_EDITOR_BOOTSTRAPPED__) return;
    g.__TAURI_EDITOR_BOOTSTRAPPED__ = true;

    void import("./editor/app.js");
  }, []);

  return (
    <div id="editorRoot">
      <div id="scrollViewport">
        <div id="spacerTop"></div>
        <div id="rowsLayer"></div>
        <div id="spacerBottom"></div>
      </div>

      <div id="overlayLayer">
        <div id="selections"></div>
        <div id="cursor"></div>
      </div>

      <div id="sidebar">
        <div id="minimap">
          <canvas id="minimapCanvas"></canvas>
          <div id="minimapViewport"></div>
        </div>
        <div id="scrollbar">
          <div id="scrollbarThumb"></div>
        </div>
      </div>

      <textarea
        id="imeInput"
        autoComplete="off"
        autoCapitalize="off"
        spellCheck={false}
      ></textarea>
    </div>
  );
}

