// swift-tools-version: 6.2.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "quiper",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Quiper",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            resources: [
                .process("logo/logo.png")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Supporting/Info.plist"])
            ]
        ),
        .testTarget(
            name: "QuiperTests",
            dependencies: ["Quiper"]
        ),
    ]
)
