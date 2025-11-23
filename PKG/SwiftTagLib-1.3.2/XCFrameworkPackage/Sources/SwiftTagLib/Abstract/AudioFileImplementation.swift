
@_implementationOnly import CxxTagLibBridge

/// Acts as common interace for `C++` `AudioFile` subtypes.
protocol AudioFileImplementation {
    init(_ fileName: std.string)

    func readMetadata(
        _ metadata: UnsafeMutablePointer<AudioMetadata>,
        _ properties: UnsafeMutablePointer<AudioProperties>,
        _ options: MetadataReadingOptions,
        _ overlayStrategy: MetadataOverlayStrategy,
        _ errorDescription: UnsafeMutablePointer<std.string>
    ) -> MetadataReadingOutcome

    func writeMetadata(
        _ metadata: UnsafeMutablePointer<AudioMetadata>,
        _ errorDescription: UnsafeMutablePointer<std.string>
    ) -> MetadataWritingOutcome
}

// MARK: - After the fact Conformances
extension CxxTagLibBridge.AudioFile.AIFF: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.DSDIFF: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.DSF: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.FLAC: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.MonkeyAudio: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.MP3: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.MP4: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.Musepack: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.OggFLAC: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.OggOpus: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.OggSpeex: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.OggVorbis: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.TrueAudio: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.WAVE: AudioFileImplementation {}
extension CxxTagLibBridge.AudioFile.WavPack: AudioFileImplementation {}
