#if os(macOS)
import SwiftUI

struct FileAccessSettingsTab: View {
    @ObservedObject var viewModel: AudioViewModel

    @State private var selectedGrantID: FileAccessGrant.ID?
    @State private var authorizationError: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: "File Access"))
                .font(.headline)

            authorizedFoldersList
        }
        .padding()
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.fileAccessGrants.map(\.id)) { _, grantIDs in
            guard let selectedGrantID, !grantIDs.contains(selectedGrantID) else { return }
            self.selectedGrantID = nil
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

    private var authorizedFoldersList: some View {
        GroupBox {
            List(selection: $selectedGrantID) {
                Text(
                    String(
                        localized: "Allow AudioMator to access the folders below between launches."
                    )
                )
                .foregroundStyle(.secondary)

                if viewModel.fileAccessGrants.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Authorized Folders"),
                        systemImage: "folder",
                        description: Text(String(localized: "Use the add button to grant access to a folder."))
                    )
                } else {
                    ForEach(viewModel.fileAccessGrants) { grant in
                        folderRow(grant)
                            .tag(grant.id)
                    }
                }

                folderActions
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(height: authorizedFoldersListHeight)
        .onDeleteCommand(perform: removeSelectedFolder)
    }

    private var authorizedFoldersListHeight: CGFloat {
        let descriptionHeight: CGFloat = 26
        let folderRowHeight: CGFloat = 39
        let actionsHeight: CGFloat = 24
        let containerInsets: CGFloat = 12
        let folderContentHeight: CGFloat

        if viewModel.fileAccessGrants.isEmpty {
            folderContentHeight = 72
        } else {
            folderContentHeight = CGFloat(viewModel.fileAccessGrants.count) * folderRowHeight
        }

        return min(
            descriptionHeight + folderContentHeight + actionsHeight + containerInsets,
            352
        )
    }

    private func folderRow(_ grant: FileAccessGrant) -> some View {
        HStack(alignment: .center) {
            Image(systemName: "folder")

            VStack(alignment: .leading, spacing: 2) {
                Text(grant.displayName)
                    .lineLimit(1)

                Text(grant.url.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                PlatformWorkspace.open(grant.url)
            } label: {
                Label(String(localized: "Open Folder"), systemImage: "arrow.up.forward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Open Folder"))
        }
        .contextMenu {
            Button(String(localized: "Remove"), role: .destructive) {
                selectedGrantID = grant.id
                removeSelectedFolder()
            }
        }
        .accessibilityLabel(grant.displayName)
        .accessibilityValue(grant.url.path(percentEncoded: false))
    }

    private var folderActions: some View {
        HStack {
            Button(action: addFolder) {
                Label(String(localized: "Add Folder"), systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Add Folder"))

            Divider()

            Button(action: removeSelectedFolder) {
                Label(String(localized: "Remove Selected Folder"), systemImage: "minus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(selectedGrantID == nil)
            .help(String(localized: "Remove Selected Folder"))

            Spacer()
        }
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

    private func addFolder() {
        switch viewModel.authorizeDefaultFileAccessFolder() {
        case .authorized:
            selectedGrantID = nil
        case .cancelled:
            break
        case .failure(let message):
            authorizationError = message
        }
    }

    private func removeSelectedFolder() {
        guard let selectedGrantID else { return }
        viewModel.removeFileAccessGrant(id: selectedGrantID)
        self.selectedGrantID = nil
    }
}
#endif
