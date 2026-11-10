import Foundation

/// Builds a genuine ID3v2.3 tag in front of an existing MP3 audio stream.
///
/// The committed MP3 fixture is ID3v2.4, and the released package does not
/// expose a public tag-version conversion API. This helper writes a minimal,
/// valid v2.3 tag so DATE can be exercised as TDAT (DDMM) rather than being
/// inferred from a v2.4 TXXX frame.
enum ID3v23FixtureBuilder {
    struct Values {
        var title = "ID3v2.3 Fixture"
        var artist = "AudioMator Tests"
        var year = "2004"
        /// Legacy DDMM text, for example April 3 is `0304`.
        var date = "0304"
        var releaseDate = ""
        var originalReleaseDate = ""
        var track = "3/12"
        var disc = "2/3"
    }

    static func makeID3v23Copy(of sourceURL: URL, values: Values = Values()) throws -> Data {
        let source = try Data(contentsOf: sourceURL)
        let audio = try audioPayload(from: source)
        var body = Data()

        appendFrame("TIT2", text: values.title, to: &body)
        appendFrame("TPE1", text: values.artist, to: &body)
        appendFrame("TYER", text: values.year, to: &body)
        appendFrame("TDAT", text: values.date, to: &body)
        if !values.releaseDate.isEmpty {
            // TDRL is a v2.4 frame registered as a v2.3 compatibility extension.
            appendFrame("TDRL", text: values.releaseDate, to: &body)
        }
        if !values.originalReleaseDate.isEmpty {
            appendFrame("TORY", text: values.originalReleaseDate, to: &body)
        }
        appendFrame("TRCK", text: values.track, to: &body)
        appendFrame("TPOS", text: values.disc, to: &body)

        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x03, 0x00, 0x00])
        tag.append(syncSafeSize(body.count))
        tag.append(body)
        tag.append(audio)
        return tag
    }

    private static func audioPayload(from source: Data) throws -> Data {
        guard source.count >= 10,
              source[0] == 0x49, source[1] == 0x44, source[2] == 0x33 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let size = Int(source[6]) << 21
            | Int(source[7]) << 14
            | Int(source[8]) << 7
            | Int(source[9])
        let tagEnd = 10 + size
        guard tagEnd <= source.count else { throw CocoaError(.fileReadCorruptFile) }
        return source.subdata(in: tagEnd..<source.count)
    }

    private static func appendFrame(_ identifier: String, text: String, to body: inout Data) {
        let payload = Data([0x00]) + Data(text.utf8) // ISO-8859-1 for ASCII text
        body.append(Data(identifier.utf8))
        body.append(bigEndianSize(payload.count))
        body.append(contentsOf: [0x00, 0x00])
        body.append(payload)
    }

    private static func bigEndianSize(_ size: Int) -> Data {
        Data([
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF),
        ])
    }

    private static func syncSafeSize(_ size: Int) -> Data {
        Data([
            UInt8((size >> 21) & 0x7F),
            UInt8((size >> 14) & 0x7F),
            UInt8((size >> 7) & 0x7F),
            UInt8(size & 0x7F),
        ])
    }
}
