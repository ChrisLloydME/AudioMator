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
                "Domain/AudioFiles/AudioFile.swift",
                "Domain/AudioFiles/MergedAudioFile.swift",
                "Domain/AudioFiles/SingleFileEditModel.swift",
                "Domain/AudioFiles/SingleFileEditModel+MetadataPipeline.swift",
                "Domain/FileSources/FileSourceModels.swift",
                "Domain/MetadataExchange/MetadataExchange.swift",
                "Domain/Rename/FileRenameTemplate.swift",
                "Domain/Rename/FilenameMetadataTemplate.swift",
                "Domain/UIState",
                "Domain/MetadataEditing/AudioMetadataPipeline.swift",
                "Infrastructure/FileSystem",
                "Infrastructure/GitHub",
                "Infrastructure/ITunes/ITunesArtworkService.swift",
                "Infrastructure/ITunes/ITunesClient.swift",
                "Infrastructure/LRCLIB/LRCLIBClient.swift",
                "Infrastructure/MusicBrainz/MusicBrainzClient.swift",
                "Infrastructure/MusicBrainz/MusicBrainzFilenameFallback.swift",
                "Infrastructure/MusicBrainz/MusicBrainzLinkParser.swift",
                "Infrastructure/MusicBrainz/MusicBrainzLuceneQueryBuilder.swift",
                "Infrastructure/MusicBrainz/MusicBrainzMatching.swift",
                "Infrastructure/MusicBrainz/MusicBrainzResultModels.swift",
                "Infrastructure/MusicBrainz/MusicBrainzSearchModels.swift",
                "Infrastructure/MusicBrainz/MusicBrainzSearchQuery.swift",
                "Infrastructure/Updates"
            ],
            sources: [
                "Core/Audio/AudioTagNumberPair.swift",
                "Core/Audio/AudioTagNumberText.swift",
                "Core/Audio/AudioFormatSupportCore.swift",
                "Core/Text/FuzzyStringSimilarity.swift",
                "Domain/AudioFiles/AudioMetadataModelCore.swift",
                "Domain/AudioFiles/AudioFileFingerprint.swift",
                "Domain/FileSources/FileCollectionCore.swift",
                "Domain/MetadataEditing/TextEditPipeline.swift",
                "Domain/MetadataEditing/FileMutationCoordinator.swift",
                "Domain/MetadataExchange/MetadataExchangeCore.swift",
                "Domain/MetadataExchange/MetadataExchangeCSV.swift",
                "Domain/MuseAmp/MuseAmpCommentIDGenerator.swift",
                "Domain/Rename/FileRenamePlanCore.swift",
                "Domain/Rename/FileRenameTemplateCore.swift",
                "Domain/Rename/FilenameMetadataExtractionCore.swift",
                "Domain/TrackRenumber/TrackRenumber.swift",
                "Infrastructure/ITunes/ITunesArtworkCore.swift",
                "Infrastructure/ITunes/ITunesProviderCore.swift",
                "Infrastructure/LRCLIB/LRCLIBCandidateRanker.swift",
                "Infrastructure/LRCLIB/LRCLIBModels.swift",
                "Infrastructure/LRCLIB/LRCLIBRequestBuilder.swift",
                "Infrastructure/MusicBrainz/MusicBrainzProviderLuceneQueryBuilder.swift",
                "Infrastructure/MusicBrainz/MusicBrainzProviderCore.swift",
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
