//
//  AudioMatorApp.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct AudioMatorApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    private let metadataPipeline: any AudioMetadataPipeline
    @StateObject private var viewModel: AudioViewModel
    @StateObject private var sharedState: SharedState
    @StateObject private var musicBrainzBrowserStore: MusicBrainzBrowserStore
    @StateObject private var metadataFilenameToolStore: MetadataFilenameToolStore
    @StateObject private var metadataEditorStore: MetadataEditorStore

    init() {
        let metadataPipeline = TagLibAudioMetadataPipeline()
        self.metadataPipeline = metadataPipeline
        _viewModel = StateObject(
            wrappedValue: AudioViewModel(metadataPipeline: metadataPipeline)
        )
        _sharedState = StateObject(wrappedValue: SharedState())
        _musicBrainzBrowserStore = StateObject(wrappedValue: MusicBrainzBrowserStore())
        _metadataFilenameToolStore = StateObject(wrappedValue: MetadataFilenameToolStore())
        _metadataEditorStore = StateObject(
            wrappedValue: MetadataEditorStore(metadataPipeline: metadataPipeline)
        )
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView(
                viewModel: viewModel,
                state: sharedState,
                musicBrainzBrowserStore: musicBrainzBrowserStore,
                metadataFilenameToolStore: metadataFilenameToolStore,
                metadataEditorStore: metadataEditorStore,
                metadataPipeline: metadataPipeline
            )
                .frame(minWidth: 900, minHeight: 600)
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
            SettingsView(sharedState: sharedState)
        }
        .defaultSize(width: 700, height: 480)

        Window("Online Metadata", id: MusicBrainzBrowserView.windowID) {
            MusicBrainzBrowserView(
                store: musicBrainzBrowserStore,
                viewModel: viewModel
            )
        }
        .defaultSize(width: 980, height: 700)

        Window("Filename & Metadata", id: MetadataFilenameWindowView.windowID) {
            MetadataFilenameWindowView(
                viewModel: viewModel,
                store: metadataFilenameToolStore
            )
        }
        .defaultSize(width: 860, height: 720)

        Window("Metadata Editor", id: MetadataEditorWindowView.windowID) {
            MetadataEditorWindowView(
                viewModel: viewModel,
                store: metadataEditorStore
            )
        }
        .defaultSize(width: 920, height: 640)
        .windowToolbarStyle(.expanded)
        #else
        WindowGroup {
            ContentView(
                viewModel: viewModel,
                state: sharedState,
                musicBrainzBrowserStore: musicBrainzBrowserStore,
                metadataFilenameToolStore: metadataFilenameToolStore,
                metadataEditorStore: metadataEditorStore,
                metadataPipeline: metadataPipeline
            )
        }
        #endif
    }
}
