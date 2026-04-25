// swift-tools-version: 6.0

import PackageDescription

let tagLibHeaderSearchPaths: [CSetting] = [
    .headerSearchPath("."),
    .headerSearchPath("taglib"),
    .headerSearchPath("taglib/taglib"),
    .headerSearchPath("taglib/taglib/toolkit"),
    .headerSearchPath("taglib/taglib/mpeg"),
    .headerSearchPath("taglib/taglib/mpeg/id3v1"),
    .headerSearchPath("taglib/taglib/mpeg/id3v2"),
    .headerSearchPath("taglib/taglib/mpeg/id3v2/frames"),
    .headerSearchPath("taglib/taglib/mp4"),
    .headerSearchPath("taglib/taglib/flac"),
    .headerSearchPath("taglib/taglib/ogg"),
    .headerSearchPath("taglib/taglib/ogg/flac"),
    .headerSearchPath("taglib/taglib/ogg/opus"),
    .headerSearchPath("taglib/taglib/ogg/speex"),
    .headerSearchPath("taglib/taglib/ogg/vorbis"),
    .headerSearchPath("taglib/taglib/ape"),
    .headerSearchPath("taglib/taglib/riff"),
    .headerSearchPath("taglib/taglib/riff/aiff"),
    .headerSearchPath("taglib/taglib/riff/wav"),
    .headerSearchPath("taglib/taglib/asf"),
    .headerSearchPath("taglib/taglib/dsf"),
    .headerSearchPath("taglib/taglib/dsdiff"),
    .headerSearchPath("taglib/taglib/it"),
    .headerSearchPath("taglib/taglib/mod"),
    .headerSearchPath("taglib/taglib/mpc"),
    .headerSearchPath("taglib/taglib/s3m"),
    .headerSearchPath("taglib/taglib/shorten"),
    .headerSearchPath("taglib/taglib/trueaudio"),
    .headerSearchPath("taglib/taglib/wavpack"),
    .headerSearchPath("taglib/taglib/xm"),
    .headerSearchPath("taglib/3rdparty/utfcpp/source"),
]

let tagLibCXXHeaderSearchPaths: [CXXSetting] = [
    .headerSearchPath("."),
    .headerSearchPath("taglib"),
    .headerSearchPath("taglib/taglib"),
    .headerSearchPath("taglib/taglib/toolkit"),
    .headerSearchPath("taglib/taglib/mpeg"),
    .headerSearchPath("taglib/taglib/mpeg/id3v1"),
    .headerSearchPath("taglib/taglib/mpeg/id3v2"),
    .headerSearchPath("taglib/taglib/mpeg/id3v2/frames"),
    .headerSearchPath("taglib/taglib/mp4"),
    .headerSearchPath("taglib/taglib/flac"),
    .headerSearchPath("taglib/taglib/ogg"),
    .headerSearchPath("taglib/taglib/ogg/flac"),
    .headerSearchPath("taglib/taglib/ogg/opus"),
    .headerSearchPath("taglib/taglib/ogg/speex"),
    .headerSearchPath("taglib/taglib/ogg/vorbis"),
    .headerSearchPath("taglib/taglib/ape"),
    .headerSearchPath("taglib/taglib/riff"),
    .headerSearchPath("taglib/taglib/riff/aiff"),
    .headerSearchPath("taglib/taglib/riff/wav"),
    .headerSearchPath("taglib/taglib/asf"),
    .headerSearchPath("taglib/taglib/dsf"),
    .headerSearchPath("taglib/taglib/dsdiff"),
    .headerSearchPath("taglib/taglib/it"),
    .headerSearchPath("taglib/taglib/mod"),
    .headerSearchPath("taglib/taglib/mpc"),
    .headerSearchPath("taglib/taglib/s3m"),
    .headerSearchPath("taglib/taglib/shorten"),
    .headerSearchPath("taglib/taglib/trueaudio"),
    .headerSearchPath("taglib/taglib/wavpack"),
    .headerSearchPath("taglib/taglib/xm"),
    .headerSearchPath("taglib/3rdparty/utfcpp/source"),
]

let package = Package(
    name: "TagLibAudioMetadata",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "TagLibAudioMetadata",
            targets: ["TagLibAudioMetadata"]
        ),
    ],
    targets: [
        .target(
            name: "CTagLibBridge",
            exclude: [
                "taglib/cmake",
                "taglib/tests",
                "taglib/COPYING.LGPL",
                "taglib/COPYING.MPL",
            ],
            publicHeadersPath: "include",
            cSettings: tagLibHeaderSearchPaths,
            cxxSettings: tagLibCXXHeaderSearchPaths,
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "TagLibAudioMetadata",
            dependencies: ["CTagLibBridge"]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
