//
//  TagLibMetadataManager.swift
//  HiFidelity
//
//  Swift wrapper for TagLib metadata extraction
//  Provides a clean Swift interface to TagLib-based metadata extraction
//

import Foundation
import AppKit

/// Swift wrapper for TagLib metadata extraction
struct TagLibMetadataManager {
    
    /// Extract metadata from an audio file using TagLib
    /// - Parameter url: URL to the audio file
    /// - Returns: TrackMetadata object populated with extracted data
    static func extractMetadata(from url: URL) -> TrackMetadata {
        var metadata = TrackMetadata(url: url)
        
        // Try extracting with TagLib
        do {
            let taglibMetadata = try TagLibMetadataExtractor.extractMetadata(from: url)
            
            // Map TagLib metadata to our TrackMetadata structure
            mapTagLibMetadataToTrackMetadata(taglibMetadata, into: &metadata)
        } catch {
            Logger.error("TagLib extraction failed for \(url.lastPathComponent): \(error.localizedDescription)")
            // Return metadata with at least filename as title
            metadata.title = url.deletingPathExtension().lastPathComponent
        }
        
        return metadata
    }
    
    /// Extract metadata asynchronously
    /// - Parameters:
    ///   - url: URL to the audio file
    ///   - completion: Completion handler with extracted metadata
    static func extractMetadata(from url: URL, completion: @escaping (TrackMetadata) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let metadata = extractMetadata(from: url)
            DispatchQueue.main.async {
                completion(metadata)
            }
        }
    }
    
    /// Check if a file format is supported by TagLib
    /// - Parameter fileExtension: File extension (without dot)
    /// - Returns: true if supported, false otherwise
    static func isSupportedFormat(_ fileExtension: String) -> Bool {
        return TagLibMetadataExtractor.isSupportedFormat(fileExtension)
    }
    
    /// Get list of all supported file extensions
    /// - Returns: Array of supported extensions
    static func supportedExtensions() -> [String] {
        return TagLibMetadataExtractor.supportedExtensions()
    }
    
    // MARK: - Private Helpers
    
    /// Map TagLib metadata object to TrackMetadata structure
    private static func mapTagLibMetadataToTrackMetadata(_ source: TagLibAudioMetadata, into metadata: inout TrackMetadata) {
        // Core metadata
        metadata.title = source.title
        metadata.artist = source.artist
        metadata.album = source.album
        metadata.albumArtist = source.albumArtist
        metadata.composer = source.composer
        metadata.genre = source.genre
        metadata.year = source.year
        
        // Track/Disc information
        if source.trackNumber > 0 {
            metadata.trackNumber = Int(source.trackNumber)
        }
        if source.totalTracks > 0 {
            metadata.totalTracks = Int(source.totalTracks)
        }
        if source.discNumber > 0 {
            metadata.discNumber = Int(source.discNumber)
        }
        if source.totalDiscs > 0 {
            metadata.totalDiscs = Int(source.totalDiscs)
        }
        
        // Audio properties
        metadata.duration = source.duration
        
        if source.bitrate > 0 {
            metadata.bitrate = Int(source.bitrate)
        }
        if source.sampleRate > 0 {
            metadata.sampleRate = Int(source.sampleRate)
        }
        if source.channels > 0 {
            metadata.channels = Int(source.channels)
        }
        if source.bitDepth > 0 {
            metadata.bitDepth = Int(source.bitDepth)
        }
        metadata.codec = source.codec
        
        // Artwork
        metadata.artworkData = source.artworkData
        
        // Additional metadata
        if source.bpm > 0 {
            metadata.bpm = Int(source.bpm)
        }
        metadata.compilation = source.compilation
        
        // Sort fields
        metadata.sortTitle = source.sortTitle
        metadata.sortArtist = source.sortArtist
        metadata.sortAlbum = source.sortAlbum
        metadata.sortAlbumArtist = source.sortAlbumArtist
        
        // Date fields
        metadata.releaseDate = source.releaseDate
        metadata.originalReleaseDate = source.originalReleaseDate
        
        // Extended metadata
        mapExtendedMetadata(source, into: &metadata.extended)
    }
    
    /// Map extended metadata fields
    private static func mapExtendedMetadata(_ source: TagLibAudioMetadata, into extended: inout ExtendedMetadata) {
        // Identifiers
        extended.isrc = source.isrc
        extended.label = source.label
        
        // MusicBrainz IDs
        extended.musicBrainzArtistId = source.musicBrainzArtistId
        extended.musicBrainzAlbumId = source.musicBrainzAlbumId
        extended.musicBrainzTrackId = source.musicBrainzTrackId
        extended.musicBrainzReleaseGroupId = source.musicBrainzReleaseGroupId
        
        // Personnel
        extended.conductor = source.conductor
        extended.remixer = source.remixer
        extended.producer = source.producer
        extended.engineer = source.engineer
        extended.lyricist = source.lyricist
        
        // Descriptive fields
        extended.subtitle = source.subtitle
        extended.grouping = source.grouping
        extended.movement = source.movement
        extended.mood = source.mood
        extended.language = source.language
        extended.key = source.musicalKey
        extended.lyrics = source.lyrics
        extended.comment = source.comment
        
        // Technical
        extended.encodedBy = source.encodedBy
        extended.encoderSettings = source.encoderSettings
        extended.copyright = source.copyright
        
        // ReplayGain
        extended.replayGainTrack = source.replayGainTrack
        extended.replayGainAlbum = source.replayGainAlbum
        
        // Sort fields
        extended.sortComposer = source.sortComposer
    }
    
    // MARK: - Batch Processing
    
    /// Extract metadata from multiple files
    /// - Parameters:
    ///   - urls: Array of file URLs
    ///   - progressHandler: Optional progress handler called after each file (current, total)
    ///   - completion: Completion handler with array of metadata
    static func extractMetadata(
        from urls: [URL],
        progressHandler: ((Int, Int) -> Void)? = nil,
        completion: @escaping ([TrackMetadata]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [TrackMetadata] = []
            
            for (index, url) in urls.enumerated() {
                let metadata = extractMetadata(from: url)
                results.append(metadata)
                
                DispatchQueue.main.async {
                    progressHandler?(index + 1, urls.count)
                }
            }
            
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
    
    /// Extract metadata from multiple files in parallel
    /// - Parameters:
    ///   - urls: Array of file URLs
    ///   - maxConcurrent: Maximum number of concurrent operations (default: 4)
    ///   - progressHandler: Optional progress handler called after each file
    ///   - completion: Completion handler with array of metadata
    static func extractMetadataParallel(
        from urls: [URL],
        maxConcurrent: Int = 4,
        progressHandler: ((Int, Int) -> Void)? = nil,
        completion: @escaping ([TrackMetadata]) -> Void
    ) {
        let queue = DispatchQueue(label: "com.hifidelity.metadata.extraction", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()
        
        var results: [Int: TrackMetadata] = [:]
        let resultsLock = NSLock()
        
        var processedCount = 0
        let countLock = NSLock()
        
        for (index, url) in urls.enumerated() {
            group.enter()
            queue.async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                
                let metadata = extractMetadata(from: url)
                
                resultsLock.lock()
                results[index] = metadata
                resultsLock.unlock()
                
                countLock.lock()
                processedCount += 1
                let current = processedCount
                countLock.unlock()
                
                DispatchQueue.main.async {
                    progressHandler?(current, urls.count)
                }
            }
        }
        
        group.notify(queue: .main) {
            // Sort results by index to maintain order
            let sortedResults = (0..<urls.count).compactMap { results[$0] }
            completion(sortedResults)
        }
    }
}

// MARK: - Convenience Extensions

extension TagLibMetadataManager {
    
    /// Extract metadata and apply it directly to a Track object
    /// - Parameters:
    ///   - track: Track object to populate
    ///   - metadata: metadata
    ///   - at: file path of audio
    static func applyMetadata(to track: inout Track, from metadata: TrackMetadata, at fileURL: URL) {
        // Core fields
        track.title = metadata.title ?? fileURL.deletingPathExtension().lastPathComponent
        track.artist = metadata.artist ?? "Unknown Artist"
        track.album = metadata.album ?? "Unknown Album"
        track.genre = metadata.genre ?? "Unknown Genre"
        track.composer = metadata.composer ?? "Unknown Composer"
        track.year = metadata.year ?? ""
        track.duration = metadata.duration
        
        track.artworkData = metadata.artworkData
        track.isMetadataLoaded = true

        // Additional metadata
        track.albumArtist = metadata.albumArtist
        track.trackNumber = metadata.trackNumber
        track.totalTracks = metadata.totalTracks
        track.discNumber = metadata.discNumber
        track.totalDiscs = metadata.totalDiscs
        track.rating = metadata.rating
        track.compilation = metadata.compilation
        track.releaseDate = metadata.releaseDate
        track.originalReleaseDate = metadata.originalReleaseDate
        track.bpm = metadata.bpm
        track.mediaType = metadata.mediaType

        // Sort fields
        track.sortTitle = metadata.sortTitle
        track.sortArtist = metadata.sortArtist
        track.sortAlbum = metadata.sortAlbum
        track.sortAlbumArtist = metadata.sortAlbumArtist

        // Audio properties
        track.bitrate = metadata.bitrate
        track.sampleRate = metadata.sampleRate
        track.channels = metadata.channels
        track.codec = metadata.codec
        track.bitDepth = metadata.bitDepth

        // File properties
        if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            track.fileSize = attributes.fileSize.map { Int64($0) }
            track.dateModified = attributes.contentModificationDate
        }

        // Extended metadata
        track.extendedMetadata = metadata.extended
    }
    
    /// Create a human-readable description of supported formats
    static var supportedFormatsDescription: String {
        let extensions = supportedExtensions()
        let uppercased = extensions.map { $0.uppercased() }
        return uppercased.joined(separator: ", ")
    }
    
    /// Validate if a URL points to a supported audio file
    /// - Parameter url: File URL to validate
    /// - Returns: true if file exists and has supported extension
    static func isValidAudioFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        let ext = url.pathExtension.lowercased()
        return isSupportedFormat(ext)
    }
}

// MARK: - Error Handling

extension TagLibMetadataManager {
    
    enum MetadataError: Error, LocalizedError {
        case fileNotFound
        case unsupportedFormat
        case extractionFailed(String)
        case invalidFileURL
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Audio file not found"
            case .unsupportedFormat:
                return "Unsupported audio file format"
            case .extractionFailed(let reason):
                return "Metadata extraction failed: \(reason)"
            case .invalidFileURL:
                return "Invalid file URL"
            }
        }
    }
    
    /// Extract metadata with Result type for better error handling
    /// - Parameter url: File URL
    /// - Returns: Result with metadata or error
    static func extractMetadataResult(from url: URL) -> Result<TrackMetadata, MetadataError> {
        guard url.isFileURL else {
            return .failure(.invalidFileURL)
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }
        
        let ext = url.pathExtension.lowercased()
        guard isSupportedFormat(ext) else {
            return .failure(.unsupportedFormat)
        }
        
        do {
            _ = try TagLibMetadataExtractor.extractMetadata(from: url)
        } catch {
            return .failure(.extractionFailed(error.localizedDescription))
        }
        
        let metadata = extractMetadata(from: url)
        return .success(metadata)
    }
}

