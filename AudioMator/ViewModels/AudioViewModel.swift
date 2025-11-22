//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AudioViewModel: ObservableObject {
    @Published private(set) var files: [AudioFile] = []

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.aiff,
        ]
        panel.title = "选择音频文件"

        guard panel.runModal() == .OK else { return }

        Task {
            var loaded: [AudioFile] = []
            for url in panel.urls {
                if let file = try? await AudioFile.load(from: url) {
                    loaded.append(file)
                }
            }
            files.append(contentsOf: loaded)
        }
    }
}
