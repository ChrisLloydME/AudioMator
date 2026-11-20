import SwiftUI

struct WatchedFolderSettingsSelection {
    var ids: Set<WatchedFolder.ID> = []

    mutating func retainAvailableFolders(_ availableIDs: Set<WatchedFolder.ID>) {
        ids.formIntersection(availableIDs)
    }

    mutating func selectNewFolders(
        previousIDs: Set<WatchedFolder.ID>,
        currentIDs: Set<WatchedFolder.ID>
    ) {
        ids = currentIDs.subtracting(previousIDs)
    }

    mutating func consumeForRemoval() -> Set<WatchedFolder.ID> {
        defer { ids.removeAll() }
        return ids
    }
}

struct FileAccessSettingsTab: View {
    @ObservedObject var viewModel: AudioViewModel

    @AppStorage("suppressesUnsavedInspectorDiscardWarning", store: AudioMatorTestHost.preferences)
    private var suppressesUnsavedInspectorDiscardWarning: Bool = false

    @State private var selectedFileAccessGrantIDs: Set<FileAccessGrant.ID> = []
    @State private var watchedFolderSelection = WatchedFolderSettingsSelection()
    @State private var authorizationError: String?
    @State private var isFileAccessInfoPresented = false
    @State private var pendingRenameRecoveryAction: RenameRecoveryPendingAction?
    @State private var renameRecoveryError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !viewModel.bookmarkPersistenceWarnings.isEmpty {
                    persistenceWarningSection
                }
                fileAccessSection
                if !viewModel.renameJournalRecovery.isEmpty || viewModel.renameJournalRecovery.isRefreshing {
                    renameJournalRecoverySection
                }
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
        .task {
            await viewModel.refreshRenameJournalRecoveryForSettings()
        }
        .onChange(of: viewModel.fileAccessGrants.map(\.id)) { _, grantIDs in
            selectedFileAccessGrantIDs.formIntersection(grantIDs)
        }
        .onChange(of: viewModel.watchedFolders.map(\.id)) { _, folderIDs in
            watchedFolderSelection.retainAvailableFolders(Set(folderIDs))
        }
        .alert(
            String(localized: "This Folder Couldn’t Be Added"),
            isPresented: authorizationErrorBinding
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(authorizationError ?? String(localized: "Access to this folder couldn’t be saved for future use."))
        }
    }

    private var persistenceWarningSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.bookmarkPersistenceWarnings, id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                String(localized: "Saved Folder Access Needs Attention"),
                systemImage: "exclamationmark.triangle"
            )
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

                Text(String(localized: "Watched folders stay in the sidebar across launches. AudioMator watches folder contents for added, removed and renamed entries; edits inside an already loaded file may need Refresh. If a folder becomes unavailable, reauthorize it or add it again."))
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
                    List(selection: $watchedFolderSelection.ids) {
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
            Button(String(localized: "Refresh"), systemImage: "arrow.clockwise") {
                viewModel.refreshWatchedFolder(id: folder.id)
            }
            Divider()
            Button(String(localized: "Remove"), role: .destructive) {
                if watchedFolderSelection.ids.contains(folder.id) {
                    removeSelectedWatchedFolders()
                } else {
                    confirmAndRemoveWatchedFolders(ids: [folder.id])
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
                MacWorkspace.open(url)
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

            Button {
                viewModel.refreshWatchedFolders(ids: watchedFolderSelection.ids)
            } label: {
                Label(String(localized: "Refresh Selected Folders"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(watchedFolderSelection.ids.isEmpty)
            .help(String(localized: "Refresh Selected Folders"))

            Divider()
                .frame(height: 16)

            Button(action: removeSelectedWatchedFolders) {
                Label(String(localized: "Remove Selected Folders"), systemImage: "minus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(watchedFolderSelection.ids.isEmpty)
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
        watchedFolderSelection.selectNewFolders(
            previousIDs: existingIDs,
            currentIDs: Set(viewModel.watchedFolders.map(\.id))
        )
    }

    private func removeSelectedFileAccessFolders() {
        guard !selectedFileAccessGrantIDs.isEmpty else { return }
        viewModel.removeFileAccessGrants(ids: selectedFileAccessGrantIDs)
        selectedFileAccessGrantIDs.removeAll()
    }

    private func removeSelectedWatchedFolders() {
        let selectedIDs = watchedFolderSelection.ids
        guard !selectedIDs.isEmpty else { return }
        confirmAndRemoveWatchedFolders(ids: selectedIDs) {
            _ = watchedFolderSelection.consumeForRemoval()
        }
    }

    private func confirmAndRemoveWatchedFolders(
        ids: Set<UUID>,
        afterRemoval: (() -> Void)? = nil
    ) {
        guard !ids.isEmpty else { return }
        let performRemoval = {
            if viewModel.removingWatchedFoldersAffectsUnsavedInspectorEdits(ids: ids) {
                viewModel.cancelEditing()
            }
            viewModel.removeWatchedFolders(ids: ids)
            afterRemoval?()
        }
        guard viewModel.removingWatchedFoldersAffectsUnsavedInspectorEdits(ids: ids) else {
            performRemoval()
            return
        }
        if suppressesUnsavedInspectorDiscardWarning {
            performRemoval()
            return
        }
        let capturedToken = viewModel.captureInspectorDiscardConfirmationToken()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Discard Inspector Edits?")
        alert.informativeText = String(localized: "Removing this watched folder affects files with unsaved inspector edits. Discard those edits to continue.")
        alert.addButton(withTitle: String(localized: "Discard Edits"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if alert.suppressionButton?.state == .on {
            suppressesUnsavedInspectorDiscardWarning = true
        }
        if let capturedToken, !viewModel.isInspectorDiscardConfirmationCurrent(capturedToken) {
            confirmAndRemoveWatchedFolders(ids: ids, afterRemoval: afterRemoval)
            return
        }
        performRemoval()
    }
    // MARK: - Rename Recovery (F2 journal)

    private enum RenameRecoveryPendingAction: Identifiable {
        case restore(UUID)
        case acknowledge(UUID)

        var id: String {
            switch self {
            case .restore(let operationID):
                return "restore-\(operationID.uuidString)"
            case .acknowledge(let operationID):
                return "acknowledge-\(operationID.uuidString)"
            }
        }
    }

    private var renameJournalRecoverySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "AudioMator found saved rename recovery records. Reviewing them is read-only; no files are moved until you explicitly restore or acknowledge an operation."))
                    .foregroundStyle(.secondary)

                if viewModel.renameJournalRecovery.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Checking saved rename recovery records…"))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(viewModel.renameJournalRecovery.issues) { issue in
                    Text(issue.message)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.renameJournalRecovery.issues.isEmpty {
                    Button(String(localized: "Show Recovery Folder in Finder")) {
                        MacWorkspace.open(viewModel.renameJournalStore.directoryURL)
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(viewModel.renameJournalRecovery.operations) { operation in
                    renameJournalOperationRow(operation)
                }

                if viewModel.renameJournalRecovery.isBusy {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(localized: "Another copy of AudioMator is using rename recovery. Wait for it to finish, then check again."))
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Check Again")) {
                            refreshRenameJournalRecovery()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let renameRecoveryError {
                    Text(renameRecoveryError)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button(String(localized: "Refresh")) {
                        refreshRenameJournalRecovery()
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.renameJournalRecovery.isRefreshing)

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                String(localized: "Rename Recovery"),
                systemImage: "arrow.uturn.backward.circle"
            )
        }
        .alert(item: $pendingRenameRecoveryAction) { action in
            switch action {
            case .restore:
                return Alert(
                    title: Text(String(localized: "Restore Original Names?")),
                    message: Text(String(localized: "AudioMator will move each recorded file back only when the exact file entry is verified. No file is overwritten. If another file now has a recorded name, restoration stops and nothing at that step is overwritten.")),
                    primaryButton: .destructive(Text(String(localized: "Restore Original Names"))) {
                        performRenameRecoveryAction(action)
                    },
                    secondaryButton: .cancel()
                )
            case .acknowledge:
                return Alert(
                    title: Text(String(localized: "Remove Rename Record?")),
                    message: Text(String(localized: "This removes the saved recovery record only. Files are not moved; a completed rename keeps its new names and an operation that never moved files stays as it is.")),
                    primaryButton: .destructive(Text(String(localized: "Remove Record"))) {
                        performRenameRecoveryAction(action)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func renameJournalOperationRow(
        _ operation: RenameJournalRecoveryOperationPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(operation.statusTitle)
                    .font(.headline)
                Spacer()
                Text(operation.phaseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(operation.entries) { entry in
                Text(String(
                    localized: "“\(entry.originalName)” → “\(entry.intendedName)” — \(entry.roleText)"
                ))
                .font(.callout)
            }

            if !operation.missingDirectoryURLs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Some recorded folders are unavailable. Restoring will ask for access to those folders first:"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(operation.missingDirectoryURLs, id: \.absoluteString) { folderURL in
                        Text(folderURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let detailText = operation.detailText {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if operation.canRestore {
                    Button(String(localized: "Restore Original Names…")) {
                        pendingRenameRecoveryAction = .restore(operation.id)
                    }
                } else if operation.canAuthorizeAndRestore {
                    Button(String(localized: "Authorize & Restore…")) {
                        pendingRenameRecoveryAction = .restore(operation.id)
                    }
                }
                if operation.canAcknowledge {
                    Button(String(localized: "Remove Record…")) {
                        pendingRenameRecoveryAction = .acknowledge(operation.id)
                    }
                }
                if viewModel.renameJournalActionInProgress == operation.id {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            .disabled(viewModel.renameJournalActionInProgress != nil)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshRenameJournalRecovery() {
        Task { @MainActor in
            await viewModel.refreshRenameJournalRecoveryForSettings()
        }
    }

    private func performRenameRecoveryAction(_ action: RenameRecoveryPendingAction) {
        Task { @MainActor in
            renameRecoveryError = nil
            let result: RenameJournalOperationActionResult
            switch action {
            case .restore(let operationID):
                result = await viewModel.restoreRenameJournalOperation(id: operationID)
            case .acknowledge(let operationID):
                result = await viewModel.acknowledgeRenameJournalOperation(id: operationID)
            }
            switch result {
            case .success:
                renameRecoveryError = nil
            case .failure(let message), .busy(let message):
                renameRecoveryError = message
            }
        }
    }
}
