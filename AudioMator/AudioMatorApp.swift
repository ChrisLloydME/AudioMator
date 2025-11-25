//
//  AudioMatorApp.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AppKit

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
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(viewModel)
                .environmentObject(sharedState)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Select All") {
                    sharedState.selectedAudioIDs = Set(viewModel.files.map { $0.id })
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}
