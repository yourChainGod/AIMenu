// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIMenu",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIMenu", targets: ["AIMenu"])
    ],
    targets: [
        .executableTarget(
            name: "AIMenu",
            path: "Sources/AIMenu",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AIMenuTests",
            dependencies: ["AIMenu"],
            path: "Tests/AIMenuTests"
        )
    ]
)
