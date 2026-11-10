import Foundation
import TagLibAudioMetadata

/// Deliberate user choices for number recovery/cleanup. There is no implicit
/// app preference, matching the package's explicit-resolution contract.
enum NumberNormalizationChoice: String, CaseIterable, Identifiable {
    case useNative
    case useLegacy
    case replace

    /// Only an empty input means removal; malformed input must never erase data.
    static func replacementComponent(_ input: String) throws -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text), value > 0 else {
            throw NSError(domain: "NumberNormalization", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Enter a positive whole number, or leave the field empty to remove it.")
            ])
        }
        return value
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useNative: L10n.string("Use Native Values")
        case .useLegacy: L10n.string("Use Legacy Values")
        case .replace: L10n.string("Replace with Explicit Values")
        }
    }
}

extension AudioViewModel {
    var numberNormalizationTargetFile: AudioFile? {
        guard selectedAudioIDs.count == 1,
              let id = selectedAudioIDs.first,
              let file = files.first(where: { $0.id == id }) else {
            return nil
        }
        return file
    }

    /// Whether the focused cleanup action is worth offering. It is available
    /// when the read found legacy aliases, private formatting provenance, or an
    /// unresolved component. Normal native-only pairs do not need it.
    func canOfferNumberNormalization(for file: AudioFile) -> Bool {
        guard let track = file.trackNumberInventory, let disc = file.discNumberInventory else {
            return false
        }
        return offersCleanup(track) || offersCleanup(disc)
    }

    private func offersCleanup(_ group: MetadataNumberGroupInventory) -> Bool {
        !group.legacyAliasIdentities.isEmpty
            || !group.privateTexts.isEmpty
            || group.number.isUnresolved
            || group.total.isUnresolved
            || group.number.state == .recoveredLegacy
            || group.total.state == .recoveredLegacy
    }

    func openNumberNormalizationPreview() {
        guard let file = numberNormalizationTargetFile else { return }
        guard !hasUnsavedInspectorChanges else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Unsaved Changes"),
                subtitle: String(localized: "Save or discard the pending inspector edits before cleaning up numbering.")
            )
            return
        }
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Unsupported Format"),
                subtitle: String(localized: "This format does not support metadata writing yet.")
            )
            return
        }
        if let accessFailure = ensureMetadataMutationDirectoryAccess(for: [file.url]) {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Folder Access Needed"),
                subtitle: accessFailure
            )
            return
        }

        numberNormalizationPreview = nil
        refreshNumberNormalizationPreview()
        isNumberNormalizationPresented = true
    }

    /// Rebuilds the preview from the current policy. Apply must never call this.
    func refreshNumberNormalizationPreview() {
        guard let file = numberNormalizationTargetFile else { return }
        do {
            let preview = try metadataPipeline.planNumberNormalization(
                at: file.url,
                policy: try effectiveNumberResolutionPolicy(),
                groups: numberNormalizationGroups
            )
            numberNormalizationPreview = preview
        } catch {
            numberNormalizationPreview = nil
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Cleanup Preview Failed"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func effectiveNumberResolutionPolicy() throws -> MetadataNumberResolutionPolicy {
        switch numberNormalizationChoice {
        case .useNative:
            return .useNative
        case .useLegacy:
            return .useLegacy
        case .replace:
            return .replace(
                number: try NumberNormalizationChoice.replacementComponent(numberNormalizationReplaceNumber),
                total: try NumberNormalizationChoice.replacementComponent(numberNormalizationReplaceTotal)
            )
        }
    }

    /// Applies exactly the captured plan. A changed file version or a stale
    /// preview is rejected by the pipeline; the plan is never regenerated here.
    @discardableResult
    func applyNumberNormalization() async -> Bool {
        guard metadataSaveProgress == nil, let preview = numberNormalizationPreview else { return false }
        guard !hasUnsavedInspectorChanges else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Unsaved Changes"),
                subtitle: String(localized: "Save or discard the pending inspector edits before cleaning up numbering.")
            )
            return false
        }
        guard let file = numberNormalizationTargetFile else { return false }

        beginMetadataSaveProgress(
            title: String(localized: "Cleaning Up Numbering"),
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )
        let result = await executeMetadataFileMutation(
            at: file.url,
            id: file.id,
            expectedFileFingerprint: file.fileFingerprint,
            syncInspectorAfterReload: true
        ) { pipeline, url in
            try pipeline.applyNumberNormalization(
                preview,
                to: url,
                expectedVersion: preview.fileVersion
            )
        }
        updateMetadataSaveProgress(
            subtitle: file.url.lastPathComponent,
            completedUnitCount: 1
        )
        endMetadataSaveProgress()

        switch result {
        case .success(let outcome):
            numberNormalizationPreview = nil
            isNumberNormalizationPresented = false
            if outcome.warnings.isEmpty {
                presentMetadataWriteHUD(
                    style: .success,
                    title: String(localized: "Numbering Updated"),
                    subtitle: file.url.lastPathComponent
                )
            } else {
                presentMetadataWriteHUD(
                    style: .warning,
                    title: String(localized: "Saved with Issues"),
                    subtitle: ([file.url.lastPathComponent] + outcome.warnings).joined(separator: "\n")
                )
            }
            return true
        case .failure(let reason):
            // A stale plan stays invalid until the user builds a fresh preview.
            numberNormalizationPreview = nil
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Cleanup Failed"),
                subtitle: reason
            )
            return false
        }
    }
}
