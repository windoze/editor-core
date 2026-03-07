// swift-tools-version: 6.0
import PackageDescription

// Rust staticlib 由 SwiftPM build plugin 触发 `cargo build` 自动生成，并落在 plugin output 目录里：
// `.build/plugins/outputs/swift/<Target>/destination/EditorCoreRustBuildPlugin/cargo-target/release/`
//
// 注：这里引用了 SwiftPM 的 plugin 输出路径约定（当前 SwiftPM 为此类 prebuildCommand 生成的稳定路径）。
let pluginOutputsBase = ".build/plugins/outputs/swift"
let cargoTargetSuffix = "destination/EditorCoreRustBuildPlugin/cargo-target/release"
let editorCoreFFIStaticLib = "\(pluginOutputsBase)/CEditorCoreFFI/\(cargoTargetSuffix)/libeditor_core_ffi.a"
let editorCoreUIFFIStaticLib = "\(pluginOutputsBase)/CEditorCoreUIFFI/\(cargoTargetSuffix)/libeditor_core_ui_ffi.a"

let package = Package(
    name: "EditorCoreFFI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EditorCoreFFI", targets: ["EditorCoreFFI"]),
        .library(name: "EditorCoreUIFFI", targets: ["EditorCoreUIFFI"]),
        .library(name: "EditorCoreAppKit", targets: ["EditorCoreAppKit"]),
        .executable(name: "EditorCoreFFIDemo", targets: ["EditorCoreFFIDemo"]),
        .executable(name: "EditorCoreSkiaAppKitDemo", targets: ["EditorCoreSkiaAppKitDemo"]),
        .executable(name: "AttoEditor", targets: ["AttoEditor"])
    ],
    targets: [
        .plugin(
            name: "EditorCoreRustBuildPlugin",
            capability: .buildTool()
        ),
        // Rust static libraries (built by Cargo) exposed to Swift via C headers.
        //
        // 说明：
        // - 我们选择“静态链接”Rust 产物到 Swift 可执行文件/测试里，避免运行时 dlopen/dlsym。
        // - Rust 侧仍保留 cdylib 产物（给其它语言/宿主用），但 Swift 包默认走 staticlib。
        //
        // 依赖约定：
        // - 先在仓库根目录构建 Rust staticlib（debug）：
        //   `cargo build -p editor-core-ffi -p editor-core-ui-ffi`
        // - 生成路径（macOS debug 默认）：
        //   `target/debug/libeditor_core_ffi.a`
        //   `target/debug/libeditor_core_ui_ffi.a`
        .target(
            name: "CEditorCoreFFI",
            path: "Sources/CEditorCoreFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                // 强制静态链接（避免 `-lfoo` 优先选择 `.dylib`）
                .unsafeFlags([editorCoreFFIStaticLib]),
            ],
            plugins: ["EditorCoreRustBuildPlugin"]
        ),
        .target(
            name: "CEditorCoreUIFFI",
            path: "Sources/CEditorCoreUIFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                // 强制静态链接（避免 `-lfoo` 优先选择 `.dylib`）
                .unsafeFlags([editorCoreUIFFIStaticLib]),
                // Skia 依赖 C++ runtime（macOS 上是 libc++）
                .linkedLibrary("c++"),
                // Skia text/layout 依赖的系统框架（静态库最终链接时需要显式带上）
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreFoundation"),
                // Skia Metal backend（GPU）依赖
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ],
            plugins: ["EditorCoreRustBuildPlugin"]
        ),
        .target(
            name: "EditorCoreFFI",
            dependencies: ["CEditorCoreFFI"],
            path: "Sources/EditorCoreFFI"
        ),
        .target(
            name: "EditorCoreUIFFI",
            dependencies: ["CEditorCoreUIFFI"],
            path: "Sources/EditorCoreUIFFI"
        ),
        .target(
            name: "EditorCoreAppKit",
            dependencies: ["EditorCoreFFI", "EditorCoreUIFFI"],
            path: "Sources/EditorCoreAppKit"
        ),
        .executableTarget(
            name: "EditorCoreFFIDemo",
            dependencies: ["EditorCoreFFI"],
            path: "Sources/EditorCoreFFIDemo"
        ),
        .executableTarget(
            name: "EditorCoreSkiaAppKitDemo",
            dependencies: ["EditorCoreAppKit", "EditorCoreUIFFI"],
            path: "Sources/EditorCoreSkiaAppKitDemo"
        ),
        .executableTarget(
            name: "AttoEditor",
            dependencies: ["EditorCoreAppKit", "EditorCoreUIFFI"],
            path: "Sources/AttoEditor"
        ),
        .testTarget(
            name: "EditorCoreFFITests",
            dependencies: ["EditorCoreFFI", "EditorCoreUIFFI"],
            path: "Tests/EditorCoreFFITests"
        ),
        .testTarget(
            name: "EditorCoreAppKitTests",
            dependencies: ["EditorCoreAppKit"],
            path: "Tests/EditorCoreAppKitTests"
        ),
    ]
)
