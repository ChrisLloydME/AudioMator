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
    @StateObject private var metadataFilenameToolStore: MetadataFilenameToolStore
    @StateObject private var metadataEditorStore: MetadataEditorStore

    init() {
        let metadataPipeline = TagLibAudioMetadataPipeline()
        // The serial XCTest host must not restore bookmarks or open the
        // developer's library before the test bundle constructs its own models.
        let testDefaults = AudioMatorTestHost.isEnabled
            ? UserDefaults(suiteName: "AudioMatorTestHost.\(UUID().uuidString)")!
            : nil
        let saveIssueLogStore = testDefaults != nil
            ? SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorTestHost-\(UUID().uuidString)-issues.json"))
            : SaveIssueLogStore()
        self.metadataPipeline = metadataPipeline
        _viewModel = StateObject(
            wrappedValue: AudioViewModel(
                watchedFolderStore: WatchedFolderStore(userDefaults: testDefaults ?? .standard),
                fileAccessGrantStore: FileAccessGrantStore(userDefaults: testDefaults ?? .standard),
                metadataPipeline: metadataPipeline,
                saveIssueLogStore: saveIssueLogStore,
                conflictPolicyDefaults: testDefaults ?? .standard
            )
        )
        _sharedState = StateObject(wrappedValue: SharedState(userDefaults: testDefaults ?? .standard))
        _saveIssueLogStore = StateObject(wrappedValue: saveIssueLogStore)
        _onlineMetadataBrowserStore = StateObject(wrappedValue: MusicBrainzBrowserStore())
        _lrclibLyricsBrowserStore = StateObject(wrappedValue: LRCLIBLyricsBrowserStore())
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
                    metadataPipeline: metadataPipeline
                )
                .frame(minWidth: 900, minHeight: 600)
            }
        }
        .commands {
            AppInfoCommands()
            SidebarCommands()
            ToolbarEditCommands(viewModel: viewModel, sharedState: sharedState)
            ViewLayoutCommands()

            CommandGroup(after: .help) {
                Button {
                    NotificationCenter.default.post(name: .showWelcomeSplash, object: nil)
                } label: {
                    Label("Show Welcome Screen", systemImage: "sparkles.rectangle.stack")
                }
            }
        }
        .defaultSize(width: 900, height: 600)

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
                viewModel: viewModel
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
