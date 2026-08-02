#if os(macOS)
import SwiftUI

struct FileAccessSettingsTab: View {
    @ObservedObject var viewModel: AudioViewModel

    @State private var selectedGrantID: FileAccessGrant.ID?
    @State private var authorizationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "File Access"))
                .font(.title3.weight(.semibold))

            authorizedFoldersList
        }
        .padding(20)
        .padding(.bottom, 8)
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
            VStack(spacing: 0) {
                List(selection: $selectedGrantID) {
                    Text(
                        String(
                            localized: "Allow AudioMator to access the folders below between launches."
                        )
                    )
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))

                    if viewModel.fileAccessGrants.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No Authorized Folders"),
                            systemImage: "folder",
                            description: Text(String(localized: "Use the add button to grant access to a folder."))
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
                    } else {
                        ForEach(viewModel.fileAccessGrants) { grant in
                            folderRow(grant)
                                .tag(grant.id)
                                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .contentMargins(.vertical, 0, for: .scrollContent)

                Divider()

                folderActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: authorizedFoldersListHeight)
        .onDeleteCommand(perform: removeSelectedFolder)
    }

    private var authorizedFoldersListHeight: CGFloat {
        let descriptionHeight: CGFloat = 36
        let toolbarHeight: CGFloat = 29
        let groupInsets: CGFloat = 18
        let contentHeight: CGFloat

        if viewModel.fileAccessGrants.isEmpty {
            contentHeight = 120
        } else {
            contentHeight = min(CGFloat(viewModel.fileAccessGrants.count) * 40, 280)
        }

        return descriptionHeight + contentHeight + toolbarHeight + groupInsets
    }

    private func folderRow(_ grant: FileAccessGrant) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.displayName)
                    .lineLimit(1)

                Text(grant.url.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: "folder")
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
        HStack(spacing: 0) {
            folderActionButton(
                systemImage: "plus",
                accessibilityLabel: String(localized: "Add Folder"),
                action: addFolder
            )

            Divider()
                .frame(height: 16)

            folderActionButton(
                systemImage: "minus",
                accessibilityLabel: String(localized: "Remove Selected Folder"),
                action: removeSelectedFolder
            )
            .disabled(selectedGrantID == nil)

            Spacer()
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func folderActionButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
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
