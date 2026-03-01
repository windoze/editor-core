// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorComponentKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EditorComponentKit", targets: ["EditorComponentKit"]),
        .executable(name: "EditorComponentDemo", targets: ["EditorComponentDemo"])
    ],
    targets: [
        .target(
            name: "EditorComponentKit",
            path: "Sources/EditorComponentKit"
        ),
        .executableTarget(
            name: "EditorComponentDemo",
            dependencies: ["EditorComponentKit"],
            path: "Sources/EditorComponentDemo"
        ),
        .testTarget(
            name: "EditorComponentKitTests",
            dependencies: ["EditorComponentKit"],
            path: "Tests/EditorComponentKitTests"
        )
    ]
)
