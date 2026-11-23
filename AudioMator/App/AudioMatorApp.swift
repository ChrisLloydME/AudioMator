//
//  AudioMatorApp.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AppKit

@main
struct AudioMatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let metadataPipeline: any AudioMetadataPipeline
    @StateObject private var viewModel: AudioViewModel
    @StateObject private var sharedState: SharedState
    @StateObject private var saveIssueLogStore: SaveIssueLogStore
    @StateObject private var onlineMetadataBrowserStore: MusicBrainzBrowserStore
    @StateObject private var lrclibLyricsBrowserStore: LRCLIBLyricsBrowserStore
    @StateObject private var onlineMetadataActivationStore: OnlineMetadataActivationStore
    private let onlineMetadataRouter: OnlineMetadataRoutingController
    @StateObject private var metadataFilenameToolStore: MetadataFilenameToolStore
    @StateObject private var metadataEditorStore: MetadataEditorStore

    init() {
        let metadataPipeline = TagLibAudioMetadataPipeline()
        // The serial XCTest host must not restore bookmarks or open the
        // developer's library before the test bundle constructs its own models.
        let preferences = AudioMatorTestHost.preferences
        let saveIssueLogStore = AudioMatorTestHost.isEnabled
            ? SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorTestHost-\(UUID().uuidString)-issues.json"))
            : SaveIssueLogStore()
        self.metadataPipeline = metadataPipeline
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: preferences),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: preferences),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: saveIssueLogStore,
            conflictPolicyDefaults: preferences
        )
        let sharedState = SharedState(userDefaults: preferences)
        _viewModel = StateObject(wrappedValue: viewModel)
        _sharedState = StateObject(wrappedValue: sharedState)
        if AudioMatorTestHost.isEnabled {
            AudioMatorTestHost.launchedViewModel = viewModel
            AudioMatorTestHost.launchedSharedState = sharedState
        }
        _saveIssueLogStore = StateObject(wrappedValue: saveIssueLogStore)
        let onlineMetadataBrowserStore = MusicBrainzBrowserStore()
        let lrclibLyricsBrowserStore = LRCLIBLyricsBrowserStore()
        let onlineMetadataActivationStore = OnlineMetadataActivationStore()
        _onlineMetadataBrowserStore = StateObject(wrappedValue: onlineMetadataBrowserStore)
        _lrclibLyricsBrowserStore = StateObject(wrappedValue: lrclibLyricsBrowserStore)
        _onlineMetadataActivationStore = StateObject(wrappedValue: onlineMetadataActivationStore)
        onlineMetadataRouter = OnlineMetadataRoutingController(
            musicBrainzStore: onlineMetadataBrowserStore,
            lrclibStore: lrclibLyricsBrowserStore,
            activationStore: onlineMetadataActivationStore
        )
        _metadataFilenameToolStore = StateObject(wrappedValue: MetadataFilenameToolStore())
        _metadataEditorStore = StateObject(
            wrappedValue: MetadataEditorStore(metadataPipeline: metadataPipeline)
        )
    }

    var body: some Scene {
        WindowGroup {
            if AudioMatorTestHost.isEnabled {
                EmptyView()
            } else {
                ContentView(
                    viewModel: viewModel,
                    state: sharedState,
                    onlineMetadataBrowserStore: onlineMetadataBrowserStore,
                    lrclibLyricsBrowserStore: lrclibLyricsBrowserStore,
                    metadataFilenameToolStore: metadataFilenameToolStore,
                    metadataEditorStore: metadataEditorStore,
                    metadataPipeline: metadataPipeline,
                    onlineMetadataRouter: onlineMetadataRouter
                )
            }
        }
        .commands {
            AppInfoCommands()
            MetadataFieldGuideCommands()
            SidebarCommands()
            ToolbarEditCommands(viewModel: viewModel, sharedState: sharedState)
            ViewLayoutCommands()
        }
        .defaultSize(width: 1_360, height: 760)
        .windowResizability(.contentMinSize)

        Window("Metadata Field Guide", id: MetadataFieldGuideView.windowID) {
            MetadataFieldGuideView()
        }
        .defaultSize(width: max(1_040, MetadataFieldGuideView.preferredSidebarWidth + 660), height: 700)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(
                viewModel: viewModel,
                sharedState: sharedState,
                saveIssueLogStore: saveIssueLogStore
            )
        }
        .defaultSize(width: 700, height: 480)

        Window(AppWindowTitle.onlineMetadataKey, id: OnlineMetadataBrowserView.windowID) {
            OnlineMetadataBrowserView(
                store: onlineMetadataBrowserStore,
                lrclibStore: lrclibLyricsBrowserStore,
                viewModel: viewModel,
                activationStore: onlineMetadataActivationStore
            )
            .audiomatorMacWindowChrome()
        }
        .defaultSize(width: 980, height: 700)

        Window(AppWindowTitle.filenameMetadataKey, id: MetadataFilenameWindowView.windowID) {
            MetadataFilenameWindowView(
                viewModel: viewModel,
                store: metadataFilenameToolStore
            )
        }
        .defaultSize(width: 860, height: 720)

        Window(AppWindowTitle.metadataEditorKey, id: MetadataEditorWindowView.windowID) {
            MetadataEditorWindowView(
                viewModel: viewModel,
                store: metadataEditorStore
            )
            .audiomatorMacWindowChrome()
        }
        .defaultSize(width: 920, height: 640)
    }
}
