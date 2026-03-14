import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// 参考 Tauri(v2)+Vite 模板：固定端口、base=./ 以支持 file:// 打包资源路径。
export default defineConfig(() => ({
  plugins: [react()],
  clearScreen: false,
  base: "./",
  server: {
    port: 1420,
    strictPort: true,
    host: process.env.TAURI_DEV_HOST || false,
    hmr: process.env.TAURI_DEV_HOST
      ? {
          protocol: "ws",
          host: process.env.TAURI_DEV_HOST,
          port: 1421,
        }
      : undefined,
  },
}));

