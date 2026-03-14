import React from "react";
import ReactDOM from "react-dom/client";

import App from "./App";
import "./style.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  // 注意：本 demo 的编辑器运行时是命令式初始化（全局监听器 + 直接持有 DOM 引用），
  // React 18 的 StrictMode 在 dev 下会触发“mount → unmount → mount”的双执行行为，
  // 会导致运行时绑定到已卸载的 DOM，从而出现“黑屏/空白但无报错”。
  //
  // 因此这里不启用 StrictMode。
  <App />,
);
