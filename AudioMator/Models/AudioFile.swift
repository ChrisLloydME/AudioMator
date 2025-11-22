//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import AVFoundation

struct AudioFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    
    let title: String?
    let artist: String?
    let album: String?
    
    init(url: URL) {
        self.url = url
        
        let asset = AVURLAsset(url: url)
        let metadata = asset.metadata
        
        self.title = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierTitle
        ).first?.stringValue
        
        self.artist = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierArtist
        ).first?.stringValue
        
        self.album = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierAlbumName
        ).first?.stringValue
    }
}
