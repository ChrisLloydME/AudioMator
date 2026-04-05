import SwiftUI

struct SidebarPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    var body: some View {
        List {
            Section {
                sourceRow(
                    title: "Session Files",
                    systemImage: "bolt.horizontal.circle",
                    selection: .quickImport
                )
            } header: {
                Text("Current Session")
            } footer: {
                Text("Files here are cleared when AudioMator closes.")
            }

            Section {
                sourceRow(
                    title: "All Watched Files",
                    systemImage: "folder.badge.gearshape",
                    selection: .watchedLibrary
                )

                if viewModel.watchedFolders.isEmpty {
                    Text("No watched folders yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.watchedFolders) { folder in
                        watchedFolderRow(folder)
                            .tag(Optional(SidebarSelection.watchedFolder(folder.id)))
                            .contextMenu {
                                Button("Remove Folder", role: .destructive) {
                                    removeWatchedFolder(folder)
                                }
                            }
                    }
                }

                Button {
                    if let selection = viewModel.addWatchedFolders() {
                        state.selectedSidebarItem = selection
                    }
                } label: {
                    Label("Add Folder…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Watched Folders")
            } footer: {
                Text("Watched folders stay in the sidebar across launches. To add files manually, select Current Session.")
            }
        }
        .listStyle(.sidebar)
    }

    private func sourceRow(
        title: String,
        systemImage: String,
        selection: SidebarSelection
    ) -> some View {
        Button {
            state.selectedSidebarItem = selection
        } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground(for: selection))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        let selection = SidebarSelection.watchedFolder(folder.id)

        return HStack(spacing: 8) {
            Button {
                state.selectedSidebarItem = selection
            } label: {
                HStack(spacing: 10) {
                    Label(folder.displayName, systemImage: "folder")
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectionBackground(for: selection))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Button {
                removeWatchedFolder(folder)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove watched folder")
        }
    }

    private func removeWatchedFolder(_ folder: WatchedFolder) {
        viewModel.removeWatchedFolder(id: folder.id)

        if state.selectedSidebarItem == .watchedFolder(folder.id) {
            state.selectedSidebarItem = viewModel.watchedFolders.isEmpty ? .quickImport : .watchedLibrary
        }
    }

    private func selectionBackground(for selection: SidebarSelection) -> some ShapeStyle {
        if state.selectedSidebarItem == selection {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }

        return AnyShapeStyle(Color.clear)
    }
}
