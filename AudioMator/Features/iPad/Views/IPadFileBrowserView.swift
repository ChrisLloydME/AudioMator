#if os(iOS)
import SwiftUI
import UIKit

struct IPadFileBrowserView: UIViewControllerRepresentable {
    let files: [AudioFile]
    @Binding var selection: Set<AudioFile.ID>
    @Binding var customOrder: [AudioFile.ID]
    @Binding var middleListSort: MiddleListSort?
    @Binding var isSelectionMode: Bool
    let onOpenSelectedFiles: () -> Void
    let onCopySelectedFilePaths: () -> Void
    let onCopySelectedFileNames: () -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onRequestEraseAllTags: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> BrowserViewController {
        context.coordinator.makeViewController()
    }

    func updateUIViewController(_ uiViewController: BrowserViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(uiViewController)
    }
}

final class BrowserViewController: UIViewController {
    let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 68, bottom: 0, right: 16)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.allowsSelection = true
        tableView.allowsMultipleSelection = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.dragInteractionEnabled = true
        tableView.keyboardDismissMode = .onDrag
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "IPadFileBrowserCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension IPadFileBrowserView {
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate {
        fileprivate var parent: IPadFileBrowserView
        private weak var tableView: UITableView?
        private var draggedIDs: [AudioFile.ID] = []
        private var renderedRows: [String] = []
        private var isApplyingSelection = false

        init(parent: IPadFileBrowserView) {
            self.parent = parent
        }

        func makeViewController() -> BrowserViewController {
            let controller = BrowserViewController()
            let tableView = controller.tableView
            tableView.dataSource = self
            tableView.delegate = self
            tableView.dragDelegate = self
            tableView.dropDelegate = self
            self.tableView = tableView
            renderedRows = currentRowFingerprints
            syncEditingState(on: tableView)
            syncSelection(on: tableView)
            return controller
        }

        func update(_ controller: BrowserViewController) {
            let tableView = self.tableView ?? controller.tableView
            self.tableView = tableView
            let currentRows = currentRowFingerprints
            if renderedRows != currentRows {
                renderedRows = currentRows
                tableView.reloadData()
            }
            syncEditingState(on: tableView)
            syncSelection(on: tableView)
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.files.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "IPadFileBrowserCell", for: indexPath)
            guard indexPath.row < parent.files.count else { return cell }

            let file = parent.files[indexPath.row]
            cell.contentConfiguration = UIHostingConfiguration {
                IPadFileBrowserRow(file: file)
            }
            .margins(.all, 0)

            var background: UIBackgroundConfiguration
            if #available(iOS 18.0, *) {
                background = .listCell()
            } else {
                background = .listPlainCell()
            }
            background.backgroundColor = .clear
            cell.backgroundConfiguration = background
            cell.selectionStyle = .default
            cell.showsReorderControl = false
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            guard !isApplyingSelection, indexPath.row < parent.files.count else { return }

            let selectedID = parent.files[indexPath.row].id
            if parent.isSelectionMode {
                var updatedSelection = parent.selection
                updatedSelection.insert(selectedID)
                parent.selection = updatedSelection
            } else {
                parent.selection = [selectedID]
            }

            syncSelection(on: tableView)
        }

        func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
            guard !isApplyingSelection, parent.isSelectionMode, indexPath.row < parent.files.count else { return }
            parent.selection.remove(parent.files[indexPath.row].id)
        }

        func tableView(
            _ tableView: UITableView,
            contextMenuConfigurationForRowAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard indexPath.row < parent.files.count else { return nil }

            let file = parent.files[indexPath.row]
            return UIContextMenuConfiguration(identifier: file.id.uuidString as NSString, previewProvider: nil) { _ in
                UIMenu(children: [
                    UIAction(title: "Open", image: UIImage(systemName: "arrow.up.forward.app")) { _ in
                        self.parent.selection = [file.id]
                        self.parent.onOpenSelectedFiles()
                    },
                    UIAction(title: "Copy Path", image: UIImage(systemName: "doc.on.doc")) { _ in
                        self.parent.selection = [file.id]
                        self.parent.onCopySelectedFilePaths()
                    },
                    UIAction(title: "Copy Filename", image: UIImage(systemName: "doc.text")) { _ in
                        self.parent.selection = [file.id]
                        self.parent.onCopySelectedFileNames()
                    },
                    UIAction(title: "Find in MusicBrainz", image: UIImage(systemName: "magnifyingglass")) { _ in
                        self.parent.selection = [file.id]
                        self.parent.onFindSelectedFileInMusicBrainz()
                    },
                    UIAction(
                        title: "Erase All Tags",
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) { _ in
                        self.parent.selection = [file.id]
                        self.parent.onRequestEraseAllTags()
                    }
                ])
            }
        }

        func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
            parent.isSelectionMode = true
            syncEditingState(on: tableView)
            return true
        }

        func tableViewDidEndMultipleSelectionInteraction(_ tableView: UITableView) {
            syncSelection(on: tableView)
        }

        func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            guard parent.middleListSort == nil, indexPath.row < parent.files.count else { return [] }

            let rowID = parent.files[indexPath.row].id
            let movingIDs: [AudioFile.ID]
            if parent.selection.contains(rowID) {
                movingIDs = parent.files.map(\.id).filter(parent.selection.contains)
            } else {
                movingIDs = [rowID]
            }

            draggedIDs = movingIDs
            let dragItem = UIDragItem(itemProvider: NSItemProvider(object: movingIDs.first!.uuidString as NSString))
            dragItem.localObject = movingIDs
            return [dragItem]
        }

        func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil && parent.middleListSort == nil
        }

        func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
            guard session.localDragSession != nil, parent.middleListSort == nil else {
                return UITableViewDropProposal(operation: .cancel)
            }
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }

        func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
            guard parent.middleListSort == nil else { return }

            let movingIDs = (coordinator.items.first?.dragItem.localObject as? [AudioFile.ID]) ?? draggedIDs
            guard !movingIDs.isEmpty else { return }

            let currentIDs = parent.files.map(\.id)
            let draggingSet = Set(movingIDs)
            let destinationRow = min(coordinator.destinationIndexPath?.row ?? currentIDs.count, currentIDs.count)
            let draggedBeforeDestination = currentIDs.prefix(destinationRow).filter(draggingSet.contains).count
            let insertionIndex = max(0, destinationRow - draggedBeforeDestination)

            var reorderedIDs = currentIDs.filter { !draggingSet.contains($0) }
            reorderedIDs.insert(contentsOf: movingIDs, at: insertionIndex)

            guard reorderedIDs != currentIDs else { return }
            parent.customOrder = reorderedIDs
            parent.middleListSort = nil
            draggedIDs.removeAll()
        }

        private func syncEditingState(on tableView: UITableView) {
            guard tableView.isEditing != parent.isSelectionMode else { return }
            tableView.setEditing(parent.isSelectionMode, animated: true)
        }

        private func syncSelection(on tableView: UITableView) {
            let selectedIndexes = IndexSet(
                parent.files.enumerated().compactMap { index, file in
                    parent.selection.contains(file.id) ? index : nil
                }
            )

            let currentIndexes = tableView.indexPathsForSelectedRows.map { IndexSet($0.map(\.row)) } ?? IndexSet()
            guard currentIndexes != selectedIndexes else { return }

            isApplyingSelection = true
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                tableView.deselectRow(at: indexPath, animated: false)
            }
            for row in selectedIndexes {
                tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
            isApplyingSelection = false
        }

        private var currentRowFingerprints: [String] {
            parent.files.map { "\($0.id.uuidString):\($0.middleListContentFingerprint)" }
        }
    }
}

private struct IPadFileBrowserRow: View {
    let file: AudioFile

    private var titleText: String {
        let trimmedTitle = file.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? file.url.deletingPathExtension().lastPathComponent : trimmedTitle
    }

    private var subtitleText: String {
        [file.artist, file.album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var tertiaryText: String {
        [file.albumArtist, file.composer, file.genre, file.year]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var trackText: String {
        if !file.trackNumberText.isEmpty { return file.trackNumberText }
        return file.track > 0 ? "\(file.track)" : ""
    }

    private var discText: String {
        if !file.discNumberText.isEmpty { return "Disc \(file.discNumberText)" }
        return file.disc > 0 ? "Disc \(file.disc)" : ""
    }

    private var trailingMetadataItems: [String] {
        [
            trackText.isEmpty ? "" : "Track \(trackText)",
            discText,
            file.composer.trimmingCharacters(in: .whitespacesAndNewlines),
            file.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: 12) {
            artworkView

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(titleText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if file.isExplicit {
                        Text("E")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                }

                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !tertiaryText.isEmpty {
                    Text(tertiaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !trailingMetadataItems.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(trailingMetadataItems.prefix(3), id: \.self) { item in
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                    }
                }
                .frame(width: 124, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = file.artwork {
            Image(platformImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
#endif
