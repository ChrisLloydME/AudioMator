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

extension Notification.Name {
    static let showWelcomeSplash = Notification.Name("showWelcomeSplash")
    static let requestMetadataDump = Notification.Name("requestMetadataDump")
    static let requestTrackRenumber = Notification.Name("requestTrackRenumber")
    static let requestMetadataFilenameRename = Notification.Name("requestMetadataFilenameRename")
    static let requestMetadataEditor = Notification.Name("requestMetadataEditor")
    static let requestMusicBrainzBrowser = Notification.Name("requestMusicBrainzBrowser")
    static let requestToggleInspector = Notification.Name("requestToggleInspector")
    static let requestClearListConfirmation = Notification.Name("requestClearListConfirmation")
    static let requestSelectAllTracks = Notification.Name("requestSelectAllTracks")
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    private let hasLaunchedKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedKey)

        if !launchedBefore {
            if let window = NSApplication.shared.windows.first {
                window.setContentSize(NSSize(width: 900, height: 600))
                window.center()
            }
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct AudioMatorApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var sharedState = SharedState()
    @StateObject private var musicBrainzBrowserStore = MusicBrainzBrowserStore()
    @StateObject private var metadataFilenameToolStore = MetadataFilenameToolStore()
    @StateObject private var metadataEditorStore = MetadataEditorStore()

    private var contentRootView: some View {
        ContentView(
            viewModel: viewModel,
            state: sharedState,
            musicBrainzBrowserStore: musicBrainzBrowserStore,
            metadataFilenameToolStore: metadataFilenameToolStore,
            metadataEditorStore: metadataEditorStore
        )
            .frame(minWidth: 900, minHeight: 600)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            contentRootView
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

        Window("MusicBrainz Browser", id: MusicBrainzBrowserView.windowID) {
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
            contentRootView
        }
        #endif
    }
}

#if os(macOS)
struct AppInfoCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                UserDefaults.standard.set(AppSettingsTab.about.rawValue, forKey: settingsSelectedTabDefaultsKey)
                openSettings()
            } label: {
                Label("About AudioMator", systemImage: "info.circle")
            }
        }
    }
}
#endif

#if os(macOS)
struct ToolbarEditCommands: Commands {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var sharedState: SharedState

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Select All") {
                NotificationCenter.default.post(name: .requestSelectAllTracks, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(sharedState.currentFileSourceMode != .quickImport)

            Button {
                if let selection = viewModel.addWatchedFolders() {
                    sharedState.selectedSidebarItem = selection
                }
            } label: {
                Label("Add Watched Folder…", systemImage: "folder.badge.plus")
            }

            Button {
                NotificationCenter.default.post(name: .requestMetadataDump, object: nil)
            } label: {
                Label(ToolbarButtonOption.tagInspector.displayName, systemImage: ToolbarButtonOption.tagInspector.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestTrackRenumber, object: nil)
            } label: {
                Label("Renumber Tracks…", systemImage: ToolbarButtonOption.renumberTracks.systemImage)
            }
            .disabled(viewModel.files.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMetadataFilenameRename, object: nil)
            } label: {
                Label("Filename & Metadata…", systemImage: ToolbarButtonOption.renameFiles.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMetadataEditor, object: nil)
            } label: {
                Label("Metadata Editor…", systemImage: ToolbarButtonOption.metadataEditor.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMusicBrainzBrowser, object: nil)
            } label: {
                Label(ToolbarButtonOption.musicBrainzBrowser.displayName, systemImage: ToolbarButtonOption.musicBrainzBrowser.systemImage)
            }

            Button(role: .destructive) {
                NotificationCenter.default.post(name: .requestClearListConfirmation, object: nil)
            } label: {
                Label(ToolbarButtonOption.clearList.displayName, systemImage: ToolbarButtonOption.clearList.systemImage)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(sharedState.currentFileSourceMode != .quickImport || viewModel.files.isEmpty)

            Divider()

            Button {
                viewModel.cancelEditing()
            } label: {
                Label("Cancel Edits", systemImage: ToolbarButtonOption.cancelEdits.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                viewModel.saveSingleEdits()
            } label: {
                Label("Save Edits", systemImage: ToolbarButtonOption.saveEdits.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)
        }
    }
}

struct ViewLayoutCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button {
                NotificationCenter.default.post(name: .requestToggleInspector, object: nil)
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }
}
#endif
