import SwiftUI

struct SidebarPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let onSelectSidebarItem: (SidebarSelection?) -> Void
    let onRemoveWatchedFolder: (WatchedFolder) -> Void
    let onRefreshWatchedFolder: (WatchedFolder) -> Void
    let onRefreshWatchedLibrary: () -> Void

    var body: some View {
        List(selection: sidebarSelection) {
            Section {
                sidebarRow(
                    title: "Session Files",
                    systemImage: "bolt.horizontal.circle"
                )
                .tag(SidebarSelection.quickImport)
                .help("Files here are cleared when AudioMator closes.")
            } header: {
                Text("Current Session")
            }

            Section {
                sidebarRow(
                    title: "All Watched Files",
                    systemImage: "folder.badge.gearshape"
                )
                .contextMenu {
                    Button("Refresh Watched Folders", systemImage: "arrow.clockwise") {
                        onRefreshWatchedLibrary()
                    }
                }
                .tag(SidebarSelection.watchedLibrary)
                .help("Watched folders stay in the sidebar across launches.")

                if viewModel.watchedFolders.isEmpty {
                    Text("No watched folders yet")
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(watchedSidebarItems, children: \.children) { item in
                        watchedSidebarRow(item)
                            .tag(item.selection)
                    }
                }

                Button {
                    if let selection = viewModel.addWatchedFolders() {
                        onSelectSidebarItem(selection)
                    }
                } label: {
                    Label("Add Folder…", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } header: {
                Text("Watched Folders")
            }
        }
        .listStyle(.sidebar)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: { state.selectedSidebarItem },
            set: { newSelection in
                guard state.selectedSidebarItem != newSelection else { return }

                DispatchQueue.main.async {
                    onSelectSidebarItem(newSelection)
                }
            }
        )
    }

    private var watchedSidebarItems: [WatchedSidebarItem] {
        viewModel.watchedFolders.map { folder in
            let childNodes = viewModel.watchedFolderHierarchies[folder.id]?.rootChildren ?? []
            return WatchedSidebarItem(
                selection: .watchedFolder(folder.id),
                kind: .root(folder),
                children: makeSubfolderItems(from: childNodes, rootFolder: folder)
            )
        }
    }

    private func makeSubfolderItems(
        from nodes: [WatchedFolderNode],
        rootFolder: WatchedFolder
    ) -> [WatchedSidebarItem]? {
        guard !nodes.isEmpty else { return nil }
        return nodes.map { node in
            WatchedSidebarItem(
                selection: node.selection,
                kind: .subfolder(rootFolder: rootFolder, node: node),
                children: makeSubfolderItems(from: node.children, rootFolder: rootFolder)
            )
        }
    }

    private func sidebarRow(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
    }

    @ViewBuilder
    private func watchedSidebarRow(_ item: WatchedSidebarItem) -> some View {
        switch item.kind {
        case .root(let folder):
            watchedFolderRow(folder)
                .contextMenu {
                    Button("Refresh Folder", systemImage: "arrow.clockwise") {
                        onRefreshWatchedFolder(folder)
                    }
                    Divider()
                    Button("Remove Folder", role: .destructive) {
                        removeWatchedFolder(folder)
                    }
                }
        case .subfolder(let rootFolder, let node):
            watchedSubfolderRow(node)
                .contextMenu {
                    Button("Refresh Folder", systemImage: "arrow.clockwise") {
                        onRefreshWatchedFolder(rootFolder)
                    }
                    Divider()
                    Button("Reveal in Finder", systemImage: "folder") {
                        MacWorkspace.reveal([node.url])
                    }
                }
        }
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            Label(folder.displayName, systemImage: "folder")
                .lineLimit(1)

            Spacer(minLength: 0)

            if let status = viewModel.directoryMonitoringStatuses[folder.id], status.isDegraded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(status.message)
                    .accessibilityLabel("Folder monitoring degraded")
                    .accessibilityValue(status.message)
            }

            if state.selectedSidebarItem == .watchedFolder(folder.id) {
                Button {
                    removeWatchedFolder(folder)
                } label: {
                    Image(systemName: "minus.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove watched folder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func watchedSubfolderRow(_ node: WatchedFolderNode) -> some View {
        Label(node.displayName, systemImage: "folder")
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(node.relativeDisplayPath)
    }

    private func removeWatchedFolder(_ folder: WatchedFolder) {
        onRemoveWatchedFolder(folder)
    }
}

private struct WatchedSidebarItem: Identifiable {
    enum Kind {
        case root(WatchedFolder)
        case subfolder(rootFolder: WatchedFolder, node: WatchedFolderNode)
    }

    let selection: SidebarSelection
    let kind: Kind
    let children: [WatchedSidebarItem]?

    var id: SidebarSelection { selection }
}
