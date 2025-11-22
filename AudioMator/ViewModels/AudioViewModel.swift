//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
import AppKit

@MainActor
final class AudioViewModel: ObservableObject {
    @Published private(set) var files: [AudioFile] = []

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["mp3", "aac", "m4a", "flac", "wav", "aiff", "alac", "ogg", "opus"]
        panel.title = "选择音频文件"

        guard panel.runModal() == .OK else { return }

        let newFiles = panel.urls.map(AudioFile.init)
        files.append(contentsOf: newFiles)
    }
}
