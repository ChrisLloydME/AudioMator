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
    static let requestToggleInspector = Notification.Name("requestToggleInspector")
    static let requestClearListConfirmation = Notification.Name("requestClearListConfirmation")
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

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, state: sharedState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
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
    }
}

struct ToolbarEditCommands: Commands {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var sharedState: SharedState

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Select All") {
                sharedState.selectedAudioIDs = Set(viewModel.files.map { $0.id })
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)

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

            Button(role: .destructive) {
                NotificationCenter.default.post(name: .requestClearListConfirmation, object: nil)
            } label: {
                Label("Clear List", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(viewModel.files.isEmpty)

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
