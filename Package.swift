// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioMatorCoreLogic",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AudioMatorCoreLogic", targets: ["AudioMatorCoreLogic"])
    ],
    targets: [
        .target(
            name: "AudioMatorCoreLogic",
            path: "AudioMator",
            exclude: [
                "App",
                "AppIcon.icon",
                "Assets.xcassets",
                "Features",
                "InfoPlist.xcstrings",
                "Localizable.xcstrings",
                "Core/Localization",
                "Core/Network",
                "Core/Platform",
                "Core/Audio/AudioFormatSupport.swift",
                "Domain/AudioFiles",
                "Domain/FileSources",
                "Domain/MetadataExchange",
                "Domain/MuseAmp",
                "Domain/Rename",
                "Domain/UIState",
                "Domain/MetadataEditing/AudioMetadataPipeline.swift",
                "Infrastructure/FileSystem",
                "Infrastructure/GitHub",
                "Infrastructure/ITunes",
                "Infrastructure/LRCLIB/LRCLIBClient.swift",
                "Infrastructure/MusicBrainz",
                "Infrastructure/Updates"
            ],
            sources: [
                "Core/Audio/AudioTagNumberPair.swift",
                "Core/Audio/AudioTagNumberText.swift",
                "Core/Text/FuzzyStringSimilarity.swift",
                "Domain/MetadataEditing/TextEditPipeline.swift",
                "Domain/TrackRenumber/TrackRenumber.swift",
                "Infrastructure/LRCLIB/LRCLIBCandidateRanker.swift",
                "Infrastructure/LRCLIB/LRCLIBModels.swift"
            ]
        ),
        .testTarget(
            name: "AudioMatorCoreLogicTests",
            dependencies: ["AudioMatorCoreLogic"],
            path: "Tests/AudioMatorCoreLogicTests"
        )
    ]
)
