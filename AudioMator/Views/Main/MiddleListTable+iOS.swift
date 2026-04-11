#if !os(macOS)
import SwiftUI

struct MiddleListTable: View {
    let files: [AudioFile]
    @Binding var selection: Set<AudioFile.ID>
    @Binding var visibleColumns: Set<MiddleListColumn>
    @Binding var customOrder: [AudioFile.ID]
    @Binding var middleListSort: MiddleListSort?
    let onOpenSelectedFiles: () -> Void
    let onRevealSelectedFilesInFinder: () -> Void
    let onCopySelectedFilePaths: () -> Void
    let onCopySelectedFileNames: () -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onRequestEraseAllTags: () -> Void

    var body: some View {
        List(files, selection: $selection) { file in
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title.isEmpty ? file.url.lastPathComponent : file.title)
                    .lineLimit(1)
                Text(file.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(file.id)
        }
    }
}
#endif
