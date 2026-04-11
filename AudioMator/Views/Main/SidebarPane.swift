import SwiftUI

struct SidebarPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

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

            #if os(macOS)
            Section {
                sidebarRow(
                    title: "All Watched Files",
                    systemImage: "folder.badge.gearshape"
                )
                .tag(SidebarSelection.watchedLibrary)
                .help("Watched folders stay in the sidebar across launches.")

                if viewModel.watchedFolders.isEmpty {
                    Text("No watched folders yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.watchedFolders) { folder in
                        watchedFolderRow(folder)
                            .contextMenu {
                                Button("Remove Folder", role: .destructive) {
                                    removeWatchedFolder(folder)
                                }
                            }
                            .tag(SidebarSelection.watchedFolder(folder.id))
                    }
                }

                Button {
                    if let selection = viewModel.addWatchedFolders() {
                        state.selectedSidebarItem = selection
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
            #endif
        }
        .listStyle(.sidebar)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: { state.selectedSidebarItem },
            set: { newSelection in
                guard state.selectedSidebarItem != newSelection else { return }

                DispatchQueue.main.async {
                    state.selectedSidebarItem = newSelection
                }
            }
        )
    }

    private func sidebarRow(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        return HStack(spacing: 8) {
            Label(folder.displayName, systemImage: "folder")
                .lineLimit(1)

            Spacer(minLength: 0)

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

    private func removeWatchedFolder(_ folder: WatchedFolder) {
        viewModel.removeWatchedFolder(id: folder.id)

        if state.selectedSidebarItem == .watchedFolder(folder.id) {
            state.selectedSidebarItem = viewModel.watchedFolders.isEmpty ? .quickImport : .watchedLibrary
        }
    }
}
