//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

class AudioViewModel: ObservableObject {
    @Published var files: [AudioFile] = []
    
    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [UTType.audio]
        } else {
            // 兼容旧系统：按扩展名过滤
            panel.allowedFileTypes = ["mp3", "m4a", "aac", "wav", "aiff", "caf"]
        }
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            let newFiles = urls.map { AudioFile(url: $0) }
            files.append(contentsOf: newFiles)
        }
    }
}
