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
                "AppIcon.icon",
                "Assets.xcassets",
                "InfoPlist.xcstrings",
                "Localizable.xcstrings",
                "Resources"
            ],
            sources: [
                "Core/Audio/AudioTagNumberPair.swift",
                "Core/Audio/MetadataDateTimeCore.swift",
                "Core/Audio/AudioTagNumberText.swift",
                "Core/Audio/AudioNumericConversion.swift",
                "Core/Audio/AudioFormatSupportCore.swift",
                "Core/Concurrency/AsyncOperationDeadline.swift",
                "Core/FileSystem/FileSystemPathSemantics.swift",
                "Core/FileSystem/QuickImportPathIndex.swift",
                "Core/FileSystem/QuickImportScopeLeases.swift",
                "Core/Text/FuzzyStringSimilarity.swift",
                "Domain/AudioFiles/AudioMetadataModelCore.swift",
                "Domain/AudioFiles/AudioFileFingerprint.swift",
                "Domain/FileSources/FileMutationDirectoryAccessPlan.swift",
                "Domain/MetadataEditing/MetadataConflictPolicy.swift",
                "Domain/MetadataEditing/TextEditPipeline.swift",
                "Domain/MetadataEditing/FileMutationCoordinator.swift",
                "Domain/MetadataExchange/MetadataExchangeCSV.swift",
                "Domain/MetadataExchange/MetadataExchangeImportCore.swift",
                "Domain/MetadataExchange/MetadataExchangeTemplateSyntax.swift",
                "Domain/MuseAmp/MuseAmpCommentIDGenerator.swift",
                "Domain/Rename/FileRenamePlanCore.swift",
                "Domain/Rename/FileRenameTemplateCore.swift",
                "Domain/Rename/FilenameMetadataExtractionCore.swift",
                "Domain/TrackRenumber/TrackRenumber.swift",
                "Infrastructure/iTunes/iTunesArtworkCore.swift",
                "Infrastructure/iTunes/iTunesProviderCore.swift",
                "Infrastructure/LRCLIB/LRCLIBCandidateRanker.swift",
                "Infrastructure/LRCLIB/LRCLIBModels.swift",
                "Infrastructure/LRCLIB/LRCLIBRequestBuilder.swift",
                "Infrastructure/MusicBrainz/MusicBrainzProviderLuceneQueryBuilder.swift",
                "Infrastructure/MusicBrainz/MusicBrainzProviderCore.swift",
                "Infrastructure/MusicBrainz/MusicBrainzRequestScheduling.swift",
                "Infrastructure/OnlineMetadata/OnlineMetadataSelectionCore.swift"
            ]
        ),
        .testTarget(
            name: "AudioMatorCoreLogicTests",
            dependencies: ["AudioMatorCoreLogic"],
            path: "Tests/AudioMatorCoreLogicTests"
        )
    ]
)
