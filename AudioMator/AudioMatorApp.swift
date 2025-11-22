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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)  // 使用苹果规范的圆角+合并 titlebar
    }
}
