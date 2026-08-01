# FFI packaging & distribution

This repo contains two C ABIs:

- `editor-core-ffi` — headless kernel APIs (commands, workspace, viewport blobs, LSP helpers, …)
- `editor-core-ui-ffi` — UI-facing APIs (Skia renderer + `EditorUi` wrapper + input helpers)

A “distributable” embedding bundle usually includes:

- C headers
  - `crates/editor-core-ffi/include/editor_core_ffi.h`
  - `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h`
- one of:
  - static libraries (`.a` / `.lib`)
  - dynamic libraries (`.dylib` / `.so` / `.dll` + import libs on Windows)
- platform-specific link/runtime dependencies (notably: Skia + C++ runtime for UI FFI)

## Build artifacts (Rust/Cargo)

From the repo root:

```bash
# release artifacts
cargo build -p editor-core-ffi -p editor-core-ui-ffi --release

# or debug artifacts
cargo build -p editor-core-ffi -p editor-core-ui-ffi
```

Cargo emits artifacts under:

- host builds: `target/<profile>/`
- cross-target builds: `target/<triple>/<profile>/` (when using `cargo build --target <triple>`)

## Packaging helper (repo-local)

This repo ships a small helper tool that copies headers + libraries into a stable layout and
writes a JSON manifest.

```bash
# Package both core + ui, static libs, release profile
cargo run -p editor-core-dist -- ffi --out dist/ffi --profile release --mode static

# Package both core + ui, static + dynamic, debug profile
cargo run -p editor-core-dist -- ffi --out dist/ffi --profile debug --mode both

# Package only core FFI
cargo run -p editor-core-dist -- ffi --out dist/ffi --profile release --mode dynamic --core-only
```

Output layout:

```
dist/ffi/<target-triple>/<profile>/
  include/
    editor_core_ffi.h
    editor_core_ui_ffi.h
  lib/
    ...
  manifest.json
```

Notes:

- The tool does **not** run `cargo build` for you; it packages *already built* outputs.
- If `--target` is not provided, the tool uses `host` as the output directory name.
- If you built without `--target`, the tool reads from `target/<profile>/`.
- If you built with `--target <triple>`, pass `--target <triple>` so the tool reads from
  `target/<triple>/<profile>/` and emits the same triple in the output directory.

## Platform notes

### macOS (Swift / AppKit)

The repo includes a SwiftPM package under `swift/` that:

- builds Rust static libraries via `EditorCoreRustBuildPlugin`
- links required system frameworks for the Skia UI backend

See `swift/Package.swift` for the up-to-date framework list.

If you embed the UI FFI (`editor-core-ui-ffi`) yourself (non-SwiftPM), note that the Skia-backed
renderer needs:

- the C++ runtime (`libc++`)
- system frameworks used by Skia text/layout and Metal backend

### Windows (MSVC, C++ / C#)

Typical distribution shapes:

- **dynamic**: ship `editor_core_ffi.dll` / `editor_core_ui_ffi.dll` (+ import libs) alongside your
  host executable; use `LoadLibrary` / P/Invoke.
- **static**: link `editor_core_ffi.lib` / `editor_core_ui_ffi.lib` into the host.

UI FFI includes a Skia build; your host must link the correct C++ runtime and ship any required
runtime dependencies when using dynamic linking.

### Linux (C/C++)

Typical distribution shapes:

- **dynamic**: ship `libeditor_core_ffi.so` / `libeditor_core_ui_ffi.so` and set rpaths or install
  into standard library paths.
- **static**: link `libeditor_core_ffi.a` / `libeditor_core_ui_ffi.a`.

For redistributable Linux builds, prefer building on an older baseline distro/toolchain to avoid
glibc version issues when shipping `.so` files.

## Versioning + SwiftPM rebuild triggers

- ABI version is exposed via `editor_core_ffi_abi_version()` (typed/binary ABI layer).
- UI ABI version and coarse feature probes are exposed via
  `editor_core_ui_ffi_abi_version()` and `editor_core_ui_ffi_feature_flags()`.
- For the Swift package, ABI/header changes should also bump:
  - `swift/Sources/CEditorCoreFFI/stamp.c`
  - `swift/Sources/CEditorCoreUIFFI/stamp.c`

These `stamp.c` files exist to force SwiftPM to relink/rebuild when exported symbols change.
The Rust build plugin also declares Rust sources, headers, these stamp files, and the reusable UI
staticlib candidates as explicit build-command inputs, so SwiftPM reruns the staticlib copy/build
step when the ABI surface or copied archive changes.
