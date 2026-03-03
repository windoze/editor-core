// swift-tools-version: 6.0
import PackageDescription

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
        .executable(name: "EditorCoreAppKitDemo", targets: ["EditorCoreAppKitDemo"]),
        .executable(name: "EditorCoreSkiaAppKitDemo", targets: ["EditorCoreSkiaAppKitDemo"])
    ],
    targets: [
        .target(
            name: "EditorCoreFFI",
            path: "Sources/EditorCoreFFI"
        ),
        .target(
            name: "EditorCoreUIFFI",
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
            name: "EditorCoreAppKitDemo",
            dependencies: ["EditorCoreAppKit", "EditorCoreFFI"],
            path: "Sources/EditorCoreAppKitDemo"
        ),
        .executableTarget(
            name: "EditorCoreSkiaAppKitDemo",
            dependencies: ["EditorCoreAppKit", "EditorCoreUIFFI"],
            path: "Sources/EditorCoreSkiaAppKitDemo"
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
