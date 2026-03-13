import SwiftUI

struct MergedMetadataSectionView: View {
    let merged: MergedAudioFile

    var body: some View {
        GroupBox("Metadata (Multiple Files)") {
            VStack(spacing: 6) {
                metadataRow(label: "Title", value: merged.title)
                Divider()
                metadataRow(label: "Artist", value: merged.artist)
                Divider()
                metadataRow(label: "Album", value: merged.album)
                Divider()
                metadataRow(label: "Composer", value: merged.composer)
                Divider()
                metadataRow(label: "Genre", value: merged.genre)
                Divider()
                metadataRow(label: "Year", value: merged.year)
                Divider()
                metadataRow(label: "Track", value: merged.track)
                Divider()
                metadataRow(label: "Disc", value: merged.disc)
                Divider()
                metadataRow(label: "Comment", value: merged.comment)
                Divider()
                metadataRow(label: "Album Artist", value: merged.albumArtist)
                Divider()
                metadataRow(label: "Release Date", value: merged.releaseDate)
                Divider()
                metadataRow(label: "Publisher", value: merged.publisher)
                Divider()
                metadataRow(label: "Copyright", value: merged.copyright)
                Divider()
                metadataRow(label: "Credits", value: merged.credits)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            FlexibleScrollableInspectorValueText(text: value ?? "—")
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }
}
