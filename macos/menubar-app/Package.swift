// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CursorDreamSkinMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CursorDreamSkinMenuBar", targets: ["CursorDreamSkinMenuBar"])
    ],
    targets: [
        .target(name: "DreamSkinCore", path: "Sources/DreamSkinCore"),
        .executableTarget(
            name: "CursorDreamSkinMenuBar",
            dependencies: ["DreamSkinCore"],
            path: "Sources/CursorDreamSkinMenuBar"
        )
    ]
)
