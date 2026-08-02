#if os(macOS)
import SwiftUI

struct FileAccessSettingsTab: View {
    @ObservedObject var viewModel: AudioViewModel

    @State private var selectedFileAccessGrantIDs: Set<FileAccessGrant.ID> = []
    @State private var selectedWatchedFolderIDs: Set<WatchedFolder.ID> = []
    @State private var authorizationError: String?
    @State private var isFileAccessInfoPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                fileAccessSection
                watchedFoldersSection
            }
            .padding(20)
            .padding(.bottom, 28)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollIndicators(.automatic, axes: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.fileAccessGrants.map(\.id)) { _, grantIDs in
            selectedFileAccessGrantIDs.formIntersection(grantIDs)
        }
        .onChange(of: viewModel.watchedFolders.map(\.id)) { _, folderIDs in
            selectedWatchedFolderIDs.formIntersection(folderIDs)
        }
        .alert(
            String(localized: "Couldn't Add Folder"),
            isPresented: authorizationErrorBinding
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(authorizationError ?? String(localized: "AudioMator couldn't save access to this folder."))
        }
    }

    private var fileAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "File Access"))
                    .font(.title3.weight(.semibold))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(localized: "Choose which folders AudioMator can access between launches."))
                        .foregroundStyle(.secondary)

                    Button {
                        isFileAccessInfoPresented.toggle()
                    } label: {
                        Label(String(localized: "About Folder Access"), systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "About Folder Access"))
                    .popover(isPresented: $isFileAccessInfoPresented) {
                        fileAccessInfoPopover
                    }
                }
            }

            authorizedFoldersList
        }
    }

    private var watchedFoldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Watched Folders"))
                    .font(.title3.weight(.semibold))

                Text(String(localized: "Watched folders stay in the sidebar across launches."))
                    .foregroundStyle(.secondary)
            }

            watchedFoldersList
        }
    }

    private var authorizedFoldersList: some View {
        GroupBox {
            VStack(spacing: 0) {
                Divider()
                    .padding(.top, 8)

                if viewModel.fileAccessGrants.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Authorized Folders"),
                        systemImage: "folder",
                        description: Text(String(localized: "Use the add button to grant access to a folder."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedFileAccessGrantIDs) {
                        ForEach(viewModel.fileAccessGrants) { grant in
                            fileAccessFolderRow(grant)
                                .tag(grant.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.visible, axes: .vertical)
                    .scrollIndicatorsFlash(onAppear: true)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .padding(.horizontal, -8)
                }

                Divider()

                fileAccessFolderActions
                    .frame(height: 20)
            }
        }
        .frame(height: folderListHeight)
        .onDeleteCommand(perform: removeSelectedFileAccessFolders)
    }

    private var watchedFoldersList: some View {
        GroupBox {
            VStack(spacing: 0) {
                Divider()
                    .padding(.top, 8)

                if viewModel.watchedFolders.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No watched folders yet"),
                        systemImage: "folder",
                        description: Text(String(localized: "Use the add button to watch a folder."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedWatchedFolderIDs) {
                        ForEach(viewModel.watchedFolders) { folder in
                            watchedFolderRow(folder)
                                .tag(folder.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.visible, axes: .vertical)
                    .scrollIndicatorsFlash(onAppear: true)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .padding(.horizontal, -8)
                }

                Divider()

                watchedFolderActions
                    .frame(height: 20)
            }
        }
        .frame(height: folderListHeight)
        .onDeleteCommand(perform: removeSelectedWatchedFolders)
    }

    private var folderListHeight: CGFloat {
        280
    }

    private var fileAccessInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Why folder access is required"), systemImage: "info.circle")
                .font(.headline)

            Text(
                String(
                    localized: "AudioMator runs in the macOS App Sandbox. It can read and edit files only in folders you choose."
                )
            )

            Text(
                String(
                    localized: "If you authorize a folder now, AudioMator remembers that permission for later saves inside it. Authorizing does not save or change any file."
                )
            )

            Text(
                String(
                    localized: "Removing a folder from this list removes AudioMator's saved access. It does not delete or modify the folder or any files inside it."
                )
            )

            Text(
                String(
                    localized: "If a folder is moved or renamed, macOS may require you to authorize it again."
                )
            )
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 360, alignment: .leading)
    }

    private func fileAccessFolderRow(_ grant: FileAccessGrant) -> some View {
        folderRow(displayName: grant.displayName, url: grant.url)
        .contextMenu {
            Button(String(localized: "Remove"), role: .destructive) {
                if selectedFileAccessGrantIDs.contains(grant.id) {
                    removeSelectedFileAccessFolders()
                } else {
                    viewModel.removeFileAccessGrant(id: grant.id)
                }
            }
        }
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        folderRow(
            displayName: folder.displayName,
            url: folder.url,
            monitoringStatus: viewModel.directoryMonitoringStatuses[folder.id]
        )
        .contextMenu {
            Button(String(localized: "Remove"), role: .destructive) {
                if selectedWatchedFolderIDs.contains(folder.id) {
                    removeSelectedWatchedFolders()
                } else {
                    viewModel.removeWatchedFolder(id: folder.id)
                }
            }
        }
    }

    private func folderRow(
        displayName: String,
        url: URL,
        monitoringStatus: DirectoryMonitoringStatus? = nil
    ) -> some View {
        HStack(alignment: .center) {
            Image(systemName: "folder")
                .foregroundStyle(.primary.opacity(0.65))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .foregroundStyle(.primary.opacity(0.82))
                    .lineLimit(1)

                Text(url.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let monitoringStatus, monitoringStatus.isDegraded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(monitoringStatus.message)
                    .accessibilityLabel(String(localized: "Folder monitoring degraded"))
                    .accessibilityValue(monitoringStatus.message)
            }

            Button {
                PlatformWorkspace.open(url)
            } label: {
                Label(String(localized: "Open Folder"), systemImage: "arrow.up.forward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary.opacity(0.82))
            .help(String(localized: "Open Folder"))
        }
        .accessibilityLabel(displayName)
        .accessibilityValue(url.path(percentEncoded: false))
    }

    private var fileAccessFolderActions: some View {
        HStack {
            Button(action: addFileAccessFolder) {
                Label(String(localized: "Add Folder"), systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Add Folder"))

            Divider()
                .frame(height: 16)

            Button(action: removeSelectedFileAccessFolders) {
                Label(String(localized: "Remove Selected Folders"), systemImage: "minus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(selectedFileAccessGrantIDs.isEmpty)
            .help(String(localized: "Remove Selected Folders"))

            Spacer()
        }
        .controlSize(.small)
    }

    private var watchedFolderActions: some View {
        HStack {
            Button(action: addWatchedFolders) {
                Label(String(localized: "Add Folder"), systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Add Watched Folder…"))

            Divider()
                .frame(height: 16)

            Button(action: removeSelectedWatchedFolders) {
                Label(String(localized: "Remove Selected Folders"), systemImage: "minus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(selectedWatchedFolderIDs.isEmpty)
            .help(String(localized: "Remove Selected Folders"))

            Spacer()
        }
        .controlSize(.small)
    }

    private var authorizationErrorBinding: Binding<Bool> {
        Binding(
            get: { authorizationError != nil },
            set: { isPresented in
                if !isPresented {
                    authorizationError = nil
                }
            }
        )
    }

    private func addFileAccessFolder() {
        switch viewModel.authorizeDefaultFileAccessFolder() {
        case .authorized:
            selectedFileAccessGrantIDs.removeAll()
        case .cancelled:
            break
        case .failure(let message):
            authorizationError = message
        }
    }

    private func addWatchedFolders() {
        let existingIDs = Set(viewModel.watchedFolders.map(\.id))
        _ = viewModel.addWatchedFolders()
        selectedWatchedFolderIDs = Set(viewModel.watchedFolders.map(\.id)).subtracting(existingIDs)
    }

    private func removeSelectedFileAccessFolders() {
        guard !selectedFileAccessGrantIDs.isEmpty else { return }
        viewModel.removeFileAccessGrants(ids: selectedFileAccessGrantIDs)
        selectedFileAccessGrantIDs.removeAll()
    }

    private func removeSelectedWatchedFolders() {
        guard !selectedWatchedFolderIDs.isEmpty else { return }
        viewModel.removeWatchedFolders(ids: selectedWatchedFolderIDs)
        selectedWatchedFolderIDs.removeAll()
    }
}
#endif
