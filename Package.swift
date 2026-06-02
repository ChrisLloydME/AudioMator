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
                "Domain/MetadataExchange/MetadataExchange.swift",
                "Domain/Rename/FileRenameTemplate.swift",
                "Domain/Rename/FilenameMetadataTemplate.swift",
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
                "Domain/MetadataExchange/MetadataExchangeCSV.swift",
                "Domain/MuseAmp/MuseAmpCommentIDGenerator.swift",
                "Domain/Rename/FileRenameTemplateCore.swift",
                "Domain/Rename/FilenameMetadataExtractionCore.swift",
                "Domain/TrackRenumber/TrackRenumber.swift",
                "Infrastructure/LRCLIB/LRCLIBCandidateRanker.swift",
                "Infrastructure/LRCLIB/LRCLIBModels.swift",
                "Infrastructure/LRCLIB/LRCLIBRequestBuilder.swift"
            ]
        ),
        .testTarget(
            name: "AudioMatorCoreLogicTests",
            dependencies: ["AudioMatorCoreLogic"],
            path: "Tests/AudioMatorCoreLogicTests"
        )
    ]
)
