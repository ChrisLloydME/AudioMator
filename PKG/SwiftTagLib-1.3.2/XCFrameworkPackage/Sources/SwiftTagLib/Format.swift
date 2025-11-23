
extension AudioFile {
    /// Describes the file format of `AudioFile`.
    public enum Format: CaseIterable {
        case aiff
        case dsdiff
        case dsf
        case flac
        case monkeysAudio
        case mp3
        case mp4
        case musepack
        case oggFlac
        case oggOpus
        case oggSpeex
        case oggVorbix
        case trueAudio
        case wave
        case wavPack
        /// should have no actual metadata
//        case shorten
        /// discared unknown/uncommon formats, have no *magic* binary number.
//        case impulseTrackerModule
//        case proTrackerModule
//        case screamTrackerModule3
//        case extendedModule
    }
}

// MARK: - AudioFormat Metatype & AudioFileImplementation Metatype
extension AudioFile.Format {
    var formatMetatype: any AudioFormat.Type {
        switch self {
            case .aiff: AIFF.self
            case .dsdiff: DSDIFF.self
            case .dsf: DSF.self
            case .flac: FLAC.self
            case .monkeysAudio: MonkeyAudio.self
            case .mp3: MP3.self
            case .mp4: MP4.self
            case .musepack: Musepack.self
            case .oggFlac: OggFLAC.self
            case .oggOpus: OggOpus.self
            case .oggSpeex: OggSpeex.self
            case .oggVorbix: OggVorbis.self
            case .trueAudio: TrueAudio.self
            case .wave: WAVE.self
            case .wavPack: WavPack.self
        }
    }

    var implementationMetatype: AudioFileImplementation.Type {
        formatMetatype.implementationMetatype
    }
}
