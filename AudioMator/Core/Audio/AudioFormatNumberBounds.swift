import Foundation

/// Declared numeric bounds for structured number components by file extension.
///
/// TagLibAudioMetadata 0.8.1 does not publish per-format component bounds through
/// its capability API, so the app declares the bounds documented in the mapping
/// contract (`Docs/Architecture/METADATA_MAPPING_SPEC.md`): MP4 pair components are
/// limited to `1...65535` with zero as the native absent-component sentinel, and
/// ID3/Xiph/APE typed components are bounded by `Int32.max`. Boundary acceptance is
/// adapter-backed (see the E1 acceptance matrix); this table is not claimed to be
/// package introspection.
nonisolated enum AudioFormatNumberBounds {
    static let int32ComponentMaximum = Int(Int32.max)
    static let mp4ComponentMaximum = 65_535

    nonisolated static func componentMaximum(forFileExtension fileExtension: String) -> Int {
        mp4Extensions.contains(fileExtension.lowercased())
            ? mp4ComponentMaximum
            : int32ComponentMaximum
    }

    nonisolated private static let mp4Extensions: Set<String> = [
        "m4a", "mp4", "m4b", "m4r", "m4p", "m4v"
    ]
}
