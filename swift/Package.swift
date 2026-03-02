// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorCoreFFI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EditorCoreFFI", targets: ["EditorCoreFFI"]),
        .library(name: "EditorCoreAppKit", targets: ["EditorCoreAppKit"]),
        .executable(name: "EditorCoreFFIDemo", targets: ["EditorCoreFFIDemo"]),
        .executable(name: "EditorCoreAppKitDemo", targets: ["EditorCoreAppKitDemo"])
    ],
    targets: [
        .target(
            name: "EditorCoreFFI",
            path: "Sources/EditorCoreFFI"
        ),
        .target(
            name: "EditorCoreAppKit",
            dependencies: ["EditorCoreFFI"],
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
        .testTarget(
            name: "EditorCoreFFITests",
            dependencies: ["EditorCoreFFI"],
            path: "Tests/EditorCoreFFITests"
        ),
    ]
)
