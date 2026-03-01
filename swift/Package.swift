// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorComponentKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EditorComponentKit", targets: ["EditorComponentKit"])
    ],
    targets: [
        .target(
            name: "EditorComponentKit",
            path: "Sources/EditorComponentKit"
        ),
        .testTarget(
            name: "EditorComponentKitTests",
            dependencies: ["EditorComponentKit"],
            path: "Tests/EditorComponentKitTests"
        )
    ]
)
