// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - Convenience
extension Target {
    var asDependency: Dependency { .target(name: name) }
    var asLibrary: Product { .library(name: name, targets: [name]) }
}

// MARK: - Configuration
let swiftSettings: [SwiftSetting] = [
    .interoperabilityMode(.Cxx),
//    .unsafeFlags(["-enable-library-evolution"]),
//    .define("ImageDataTransformationEnabled"),
]

/// only used as a testing convenience, should not be exposed or enabled in release
let includeMetadataReader: Bool = false

// MARK: - Targets
let taglib = Target.target(
    name: "taglib",
    exclude: [
        /// utility
        "make-headers-public.sh",
        /// taglib
        "taglib/README.md",
        "taglib/3rdparty/",
        "taglib/bindings/",
        "taglib/bindings/README",
        "taglib/bindings/c/CMakeLists.txt",
        "taglib/bindings/c/taglib_c.pc.cmake",
        "taglib/bindings/CMakeLists.txt",
        "taglib/cmake/",
        "taglib/doc/",
        "taglib/examples/",
        "taglib/tests/",
        "taglib/AUTHORS",
        "taglib/CHANGELOG.md",
        "taglib/cmake_uninstall.cmake.in",
        "taglib/CMakeLists.txt",
        "taglib/config.h.cmake",
        "taglib/ConfigureChecks.cmake",
        "taglib/COPYING.LGPL",
        "taglib/COPYING.MPL",
        "taglib/Doxyfile.cmake",
        "taglib/INSTALL.md",
        "taglib/README.md",
        "taglib/taglib/taglib_config.h.cmake",
        "taglib/taglib-config.cmake",
        "taglib/taglib-config.cmake.in",
        "taglib/taglib-config.cmd.cmake",
        "taglib/taglib.pc.cmake",
        "taglib/taglib/CMakeLists.txt",
        "taglib/taglib/ape/ape-tag-format.txt",
        "taglib/taglib/mpeg/id3v2/id3v2.2.0.txt",
        "taglib/taglib/mpeg/id3v2/id3v2.3.0.txt",
        "taglib/taglib/mpeg/id3v2/id3v2.4.0-frames.txt",
        "taglib/taglib/mpeg/id3v2/id3v2.4.0-structure.txt",
        "taglib/taglib/toolkit/propertymapping.dox",
        "taglib/taglib/toolkit/tmap.tcc",
        "taglib/taglib/toolkit/tlist.tcc",
        /// utfcpp
        "utfcpp/README.md",
        "utfcpp/extern/",
        "utfcpp/tests/",
        "utfcpp/CMakeLists.txt",
        "utfcpp/LICENSE",
        "utfcpp/utf8cppConfig.cmake.in",
    ],
    sources: [
        "utfcpp/source/",
        "taglib/bindings/c/",
        "taglib/taglib/",
    ],
    cxxSettings: [
        .headerSearchPath("include/taglib"),
        .headerSearchPath("utfcpp/source/"),
    ]
)
/// C++ intermediate layer replacing AudioMetadata class hierarchy from SFBAudioEngine.
let taglibBridge = Target.target(
    name: "CxxTagLibBridge",
    dependencies: [
        taglib.asDependency,
    ],
    publicHeadersPath: "include",
    cxxSettings: [
        .headerSearchPath("include/CxxTagLibBridge")
    ],
    linkerSettings: [
        .linkedFramework("CoreFoundation"),
        .linkedFramework("ImageIO"),
    ]
)
/// Swift facade
let swiftTagLib = Target.target(
    name: "SwiftTagLib",
    dependencies: [
        taglibBridge.asDependency,
    ],
    swiftSettings: swiftSettings
)

let tests = Target.testTarget(
    name: "SwiftTagLibTests",
    dependencies: [
        swiftTagLib.asDependency,
    ],
    swiftSettings: swiftSettings
)

// MARK: - Package
let package = Package(
    name: "SwiftTagLib",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        taglib.asLibrary,
        taglibBridge.asLibrary,
        swiftTagLib.asLibrary,
    ],
    targets: [
        taglib,
        taglibBridge,
        swiftTagLib,
        tests
    ],
    cxxLanguageStandard: .cxx2b
)

// MARK: - MetadataReader Executable
if includeMetadataReader {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.5.0")),
    ]
    let metadataReader = Target.executableTarget(
        name: "MetadataReader",
        dependencies: [
            swiftTagLib.asDependency,
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        swiftSettings: swiftSettings
    )
    package.targets.append(metadataReader)
    package.products.append(.executable(name: "read-metadata", targets: [metadataReader.name]))
}
