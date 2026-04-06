//
//  AudioMatorApp.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let showWelcomeSplash = Notification.Name("showWelcomeSplash")
    static let requestMetadataDump = Notification.Name("requestMetadataDump")
    static let requestTrackRenumber = Notification.Name("requestTrackRenumber")
    static let requestMetadataFilenameRename = Notification.Name("requestMetadataFilenameRename")
    static let requestMusicBrainzBrowser = Notification.Name("requestMusicBrainzBrowser")
    static let requestToggleInspector = Notification.Name("requestToggleInspector")
    static let requestClearListConfirmation = Notification.Name("requestClearListConfirmation")
    static let requestSelectAllTracks = Notification.Name("requestSelectAllTracks")
}

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

@main
struct AudioMatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var sharedState = SharedState()
    @StateObject private var musicBrainzBrowserStore = MusicBrainzBrowserStore()

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: viewModel,
                state: sharedState,
                musicBrainzBrowserStore: musicBrainzBrowserStore
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

        Window("MusicBrainz Browser", id: MusicBrainzBrowserView.windowID) {
            MusicBrainzBrowserView(store: musicBrainzBrowserStore)
        }
        .defaultSize(width: 980, height: 700)
    }
}

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
                Label("Tag Inspector", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestTrackRenumber, object: nil)
            } label: {
                Label("Renumber Tracks…", systemImage: "number")
            }
            .disabled(viewModel.files.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMetadataFilenameRename, object: nil)
            } label: {
                Label("Rename Files…", systemImage: "pencil.line")
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMusicBrainzBrowser, object: nil)
            } label: {
                Label("MusicBrainz Browser", systemImage: "network")
            }

            Button(role: .destructive) {
                NotificationCenter.default.post(name: .requestClearListConfirmation, object: nil)
            } label: {
                Label("Clear List", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(sharedState.currentFileSourceMode != .quickImport || viewModel.files.isEmpty)

            Divider()

            Button {
                viewModel.cancelEditing()
            } label: {
                Label("Cancel Edits", systemImage: "xmark.circle")
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                viewModel.saveSingleEdits()
            } label: {
                Label("Save Edits", systemImage: "square.and.arrow.down")
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
