import Foundation
@testable import AudioMator

enum WorkbenchRecordingBehavior: Sendable {
    case success
    case failure
    case timeout
}

struct OnlineMetadataWorkbenchPerformanceScenario {
    let trackCount: Int
    let files: [AudioFile]
    let musicBrainzRelease: MusicBrainzReleaseDetail
    let musicBrainzPreview: MusicBrainzReleaseMatchPreview
    let iTunesDetail: iTunesAlbumDetail
    let iTunesPreview: iTunesAlbumMatchPreview
    let recordingBehaviors: [String: WorkbenchRecordingBehavior]
}

enum OnlineMetadataWorkbenchPerformanceScenarioFactory {
    static let supportedTrackCounts = [10, 50, 200]

    static func make(trackCount: Int) -> OnlineMetadataWorkbenchPerformanceScenario {
        precondition(supportedTrackCounts.contains(trackCount))

        let discCount = 2
        let tracksPerDisc = trackCount / discCount
        let unmatchedCount = max(2, trackCount / 10)
        let matchedCount = trackCount - unmatchedCount
        let longLocalText = String(repeating: " local metadata with punctuation — ", count: 6)
        let longRemoteText = String(repeating: " remote metadata with punctuation — ", count: 6)

        let files = (0..<trackCount).map { index in
            let url = URL(fileURLWithPath: "/tmp/offline-workbench-\(index + 1).flac")
            let discNumber = min((index / tracksPerDisc) + 1, discCount)
            let trackNumber = (index % tracksPerDisc) + 1
            return AudioFileTestFactory.make(
                id: deterministicUUID(index: index),
                url: url,
                title: "Local Track \(index + 1)\(longLocalText)",
                artist: "Local Artist \(index % 7)",
                album: "Local Album\(longLocalText)",
                composer: "Local Composer \(index % 5)",
                genre: index.isMultiple(of: 2) ? "Local Rock" : "Local Jazz",
                comment: longLocalText,
                track: trackNumber,
                trackTotal: tracksPerDisc,
                disc: discNumber,
                discTotal: discCount,
                trackNumberText: "\(trackNumber)/\(tracksPerDisc)",
                discNumberText: "\(discNumber)/\(discCount)",
                year: "1999",
                albumArtist: "Local Album Artist",
                releaseDate: "1999-12-31",
                contentAdvisory: index.isMultiple(of: 3) ? .explicit : nil,
                duration: Double(180 + index),
                fileFingerprint: AudioFileFingerprint(
                    normalizedPath: url.path,
                    fileSize: UInt64(10_000 + index),
                    contentModificationDate: Date(timeIntervalSince1970: 1_700_000_000),
                    fileSystemNumber: 1,
                    fileNumber: UInt64(index + 1)
                )
            )
        }

        let musicBrainzInputs = files.enumerated().map { index, file in
            MusicBrainzFileSearchInput(
                id: file.id.uuidString,
                displayTitle: file.url.lastPathComponent,
                title: file.title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: String(file.track),
                discNumber: String(file.disc),
                trackTotal: file.trackTotal,
                durationMilliseconds: Int(file.duration * 1_000),
                releaseDate: file.releaseDate,
                isrc: index.isMultiple(of: 4) ? "LOCALISRC\(index)" : "",
                barcode: index.isMultiple(of: 5) ? "000000000000\(index)" : ""
            )
        }
        let musicBrainzTracks = (0..<trackCount).map { index in
            let discNumber = min((index / tracksPerDisc) + 1, discCount)
            let trackNumber = (index % tracksPerDisc) + 1
            return MusicBrainzReleaseMatchTrack(
                id: "mb-track-\(index + 1)",
                mediumTitle: "Disc \(discNumber)\(longRemoteText)",
                mediumFormat: discNumber == 1 ? "Digital Media" : "12-inch Vinyl",
                mediumPosition: discNumber,
                mediumTrackCount: tracksPerDisc,
                releaseMediumCount: discCount,
                number: String(trackNumber),
                title: "Remote Track \(index + 1)\(longRemoteText)",
                artistCredit: "Remote Artist \(index % 9)",
                durationMilliseconds: (200 + index) * 1_000,
                recordingID: "mb-recording-\(index + 1)",
                isrcs: ["REMOTEISRC\(String(format: "%06d", index + 1))"]
            )
        }
        let musicBrainzAssignments = (0..<matchedCount).map { index in
            let trackIndex = index == 1 ? 0 : index
            return MusicBrainzReleaseMatchAssignment(
                id: "mb-assignment-\(index + 1)",
                file: musicBrainzInputs[index],
                track: musicBrainzTracks[trackIndex],
                score: 0.8 + Double(index % 10) / 100,
                reason: "deterministic duplicate/multi-disc fixture"
            )
        }
        let assignedMusicBrainzTrackIDs = Set(musicBrainzAssignments.map(\.track.id))
        let musicBrainzPreview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: trackCount,
            matchedAssignments: musicBrainzAssignments,
            unmatchedFiles: Array(musicBrainzInputs.suffix(unmatchedCount)),
            unassignedTracks: musicBrainzTracks.filter { !assignedMusicBrainzTrackIDs.contains($0.id) },
            averageTrackScore: 0.85,
            overallScore: 0.82,
            selectionLooksMixed: true
        )
        let musicBrainzMedia = (1...discCount).map { discNumber in
            let tracks = musicBrainzTracks.filter { $0.mediumPosition == discNumber }
            return MusicBrainzReleaseDetail.Medium(
                id: "mb-medium-\(discNumber)",
                title: "Disc \(discNumber)\(longRemoteText)",
                format: discNumber == 1 ? "Digital Media" : "12-inch Vinyl",
                trackCount: tracks.count,
                discIDs: ["disc-id-\(discNumber)"],
                tracks: tracks.map { track in
                    MusicBrainzReleaseDetail.Medium.Track(
                        id: track.id,
                        number: track.number,
                        title: track.title,
                        artistCredit: track.artistCredit,
                        durationMilliseconds: track.durationMilliseconds,
                        recordingID: track.recordingID,
                        isrcs: track.isrcs
                    )
                }
            )
        }
        let musicBrainzRelease = MusicBrainzReleaseDetail(
            id: "mb-release-offline-\(trackCount)",
            title: "Remote Album\(longRemoteText)",
            artistCredit: "Remote Album Artist",
            date: "2026-07-28",
            country: "US",
            status: "Official",
            barcode: "1234567890123",
            packaging: "Gatefold Cover",
            asin: "OFFLINEASIN",
            quality: "high",
            language: "eng",
            script: "Latn",
            annotation: longRemoteText,
            genres: [MusicBrainzTerm(name: "Alternative Rock", count: 30)],
            tags: [MusicBrainzTerm(name: "offline fixture", count: 20)],
            releaseGroupTitle: "Remote Album Group",
            releaseGroupID: "mb-release-group-offline",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: ["Compilation"],
            labels: [
                MusicBrainzReleaseDetail.LabelInfo(
                    id: "mb-label",
                    labelName: "Remote Label\(longRemoteText)",
                    catalogNumber: "CAT-\(trackCount)"
                )
            ],
            media: musicBrainzMedia,
            selectionMatchPreview: musicBrainzPreview
        )

        let iTunesInputs = files.enumerated().map { index, file in
            iTunesFileSearchInput(
                id: file.id.uuidString,
                displayTitle: file.url.lastPathComponent,
                title: file.title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: String(file.track),
                discNumber: String(file.disc),
                trackTotal: file.trackTotal,
                durationMilliseconds: Int(file.duration * 1_000),
                releaseDate: file.releaseDate,
                barcode: index.isMultiple(of: 5) ? "000000000000\(index)" : "",
                itunesAlbumID: "",
                itunesArtistID: "",
                itunesCatalogID: ""
            )
        }
        let iTunesTracks = (0..<trackCount).map { index in
            let discNumber = min((index / tracksPerDisc) + 1, discCount)
            let trackNumber = (index % tracksPerDisc) + 1
            return iTunesTrackResult(
                trackID: 10_000 + index,
                collectionID: 2_000,
                artistID: 3_000 + (index % 9),
                collectionArtistID: 3_000,
                trackName: "Remote Track \(index + 1)\(longRemoteText)",
                artistName: "Remote Artist \(index % 9)",
                collectionArtistName: "Remote Album Artist",
                collectionName: "Remote Album\(longRemoteText)",
                trackNumber: trackNumber,
                trackCount: tracksPerDisc,
                discNumber: discNumber,
                discCount: discCount,
                durationMilliseconds: (200 + index) * 1_000,
                releaseDate: "2026-07-28T00:00:00Z",
                primaryGenreName: index.isMultiple(of: 2) ? "Alternative" : "Rock",
                country: "USA",
                copyright: "Copyright\(longRemoteText)",
                contentAdvisoryRating: index.isMultiple(of: 3) ? "Explicit" : "Clean",
                kind: "song",
                wrapperType: "track",
                trackExplicitness: index.isMultiple(of: 3) ? "explicit" : "cleaned",
                collectionExplicitness: "explicit",
                trackViewURL: nil,
                collectionViewURL: nil,
                artistViewURL: nil
            )
        }
        let iTunesAssignments = (0..<matchedCount).map { index in
            let trackIndex = index == 1 ? 0 : index
            return iTunesAlbumMatchAssignment(
                id: "itunes-assignment-\(index + 1)",
                file: iTunesInputs[index],
                track: iTunesTracks[trackIndex],
                score: 0.8 + Double(index % 10) / 100,
                reason: "deterministic duplicate/multi-disc fixture"
            )
        }
        let assignediTunesTrackIDs = Set(iTunesAssignments.map(\.track.trackID))
        let iTunesPreview = iTunesAlbumMatchPreview(
            totalSelectedFiles: trackCount,
            matchedAssignments: iTunesAssignments,
            unmatchedFiles: Array(iTunesInputs.suffix(unmatchedCount)),
            unassignedTracks: iTunesTracks.filter { !assignediTunesTrackIDs.contains($0.trackID) },
            overallScore: 0.82
        )
        let iTunesAlbum = iTunesAlbumResult(
            collectionID: 2_000,
            artistID: 3_000,
            collectionArtistID: 3_000,
            collectionName: "Remote Album\(longRemoteText)",
            artistName: "Remote Album Artist",
            collectionArtistName: "Remote Album Artist",
            trackCount: trackCount,
            releaseDate: "2026-07-28T00:00:00Z",
            primaryGenreName: "Alternative Rock",
            country: "USA",
            copyright: "Copyright\(longRemoteText)",
            contentAdvisoryRating: "Explicit",
            collectionExplicitness: "explicit",
            collectionViewURL: nil,
            artistViewURL: nil,
            selectionMatchPreview: iTunesPreview,
            selectionMatchScore: 0.82
        )

        return OnlineMetadataWorkbenchPerformanceScenario(
            trackCount: trackCount,
            files: files,
            musicBrainzRelease: musicBrainzRelease,
            musicBrainzPreview: musicBrainzPreview,
            iTunesDetail: iTunesAlbumDetail(
                album: iTunesAlbum,
                tracks: iTunesTracks,
                selectionMatchPreview: iTunesPreview
            ),
            iTunesPreview: iTunesPreview,
            recordingBehaviors: Dictionary(
                uniqueKeysWithValues: musicBrainzTracks.map { track in
                    let index = Int(track.id.split(separator: "-").last ?? "1") ?? 1
                    let behavior: WorkbenchRecordingBehavior
                    switch index % 3 {
                    case 0: behavior = .timeout
                    case 1: behavior = .success
                    default: behavior = .failure
                    }
                    return (track.recordingID, behavior)
                }
            )
        )
    }

    private static func deterministicUUID(index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }
}
