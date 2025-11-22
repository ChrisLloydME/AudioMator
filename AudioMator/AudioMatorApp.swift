//
//  AudioMatorApp.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI

@main
struct AudioMatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
}
