// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTagLib",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SwiftTagLib",
            targets: [
                "SwiftTagLib",
                "CxxTagLibBridge",
                "taglib",
            ]
        )
    ],
    targets: [
        .target(
            name: "SwiftTagLib",
            dependencies: ["CxxTagLibBridge", "taglib"],
            path: "Sources/SwiftTagLib"
        ),
        .target(
            name: "CxxTagLibBridge",
            dependencies: ["taglib"],
            path: "Sources/CxxTagLibBridge"
        ),
        .target(
            name: "taglib",
            path: "Sources/taglib"
        )
    ]
)
