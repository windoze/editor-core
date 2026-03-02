// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorCoreFFI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EditorCoreFFI", targets: ["EditorCoreFFI"]),
        .executable(name: "EditorCoreFFIDemo", targets: ["EditorCoreFFIDemo"])
    ],
    targets: [
        .target(
            name: "EditorCoreFFI",
            path: "Sources/EditorCoreFFI"
        ),
        .executableTarget(
            name: "EditorCoreFFIDemo",
            dependencies: ["EditorCoreFFI"],
            path: "Sources/EditorCoreFFIDemo"
        ),
        .testTarget(
            name: "EditorCoreFFITests",
            dependencies: ["EditorCoreFFI"],
            path: "Tests/EditorCoreFFITests"
        ),
    ]
)

