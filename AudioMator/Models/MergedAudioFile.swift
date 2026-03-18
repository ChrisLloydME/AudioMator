struct MergedAudioFile {
    let title: String
    let artist: String
    let album: String
    let composer: String
    let genre: String
    let year: String
    let track: String
    let disc: String
    let comment: String
    let albumArtist: String
    let releaseDate: String
    let publisher: String
    let copyright: String
    let credits: String

    init(files: [AudioFile]) {
        func merge(_ values: [String]) -> String {
            guard let first = values.first else { return "—" }
            return values.allSatisfy { $0 == first } ? first : "—"
        }

        title = merge(files.map { $0.title })
        artist = merge(files.map { $0.artist })
        album = merge(files.map { $0.album })
        composer = merge(files.map { $0.composer })
        genre = merge(files.map { $0.genre })
        year = merge(files.map { $0.year })
        track = merge(files.map { $0.trackNumberText })
        disc = merge(files.map { $0.discNumberText })
        comment = merge(files.map { $0.comment })
        albumArtist = merge(files.map { $0.albumArtist })
        releaseDate = merge(files.map { $0.releaseDate })
        publisher = merge(files.map { $0.publisher })
        copyright = merge(files.map { $0.copyright })
        credits = merge(files.map { $0.credits })
    }
}
