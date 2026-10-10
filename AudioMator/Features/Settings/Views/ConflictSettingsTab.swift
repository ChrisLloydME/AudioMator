import SwiftUI

struct ConflictSettingsTab: View {
    @AppStorage private var policyRawValue: String

    init(defaults: UserDefaults) {
        _policyRawValue = AppStorage(
            wrappedValue: MetadataConflictPolicy.mergeNonConflicting.rawValue,
            MetadataConflictPolicy.defaultsKey,
            store: defaults
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "When edited files change on disk"), selection: policyBinding) {
                    Text(String(localized: "Merge non-conflicting changes (Recommended)"))
                        .tag(MetadataConflictPolicy.mergeNonConflicting)
                    Text(String(localized: "Prefer my changes"))
                        .tag(MetadataConflictPolicy.preferUserChanges)
                    Text(String(localized: "Prefer disk changes"))
                        .tag(MetadataConflictPolicy.preferDiskChanges)
                    Text(String(localized: "Require manual reload"))
                        .tag(MetadataConflictPolicy.requireReload)
                }
                .pickerStyle(.radioGroup)

                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conflictPolicyExplanation")
            } header: {
                Text(String(localized: "Conflict Handling"))
            }

            Section {
                Text(String(localized: "Applies when saving Inspector and Metadata Editor drafts. Non-conflicting edits are merged under either priority strategy. Track number and total tracks, disc number and total discs, and artwork are handled as groups."))
                Text(String(localized: "Files are checked again before saving. If a file was replaced, cannot be read reliably, or changes again during saving, the save stops and your draft is kept. Preview-based tools and Clear All Metadata always require an unchanged revision."))
                Text(String(localized: "Selected files are checked when AudioMator becomes active. Clean Inspector fields refresh automatically; unsaved drafts are preserved. Watched folders continue to rescan after folder changes. This setting controls saving, not continuous monitoring of every open file."))
            } header: {
                Text(String(localized: "Safety and Reload"))
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var policyBinding: Binding<MetadataConflictPolicy> {
        Binding(
            get: { MetadataConflictPolicy(rawValue: policyRawValue) ?? .mergeNonConflicting },
            set: { policyRawValue = $0.rawValue }
        )
    }

    private var explanation: String {
        switch policyBinding.wrappedValue {
        case .mergeNonConflicting:
            String(localized: "Automatically keeps changes to different fields. If both sides changed the same field and a safe merge cannot be verified, saving stops and your draft is kept so you can choose how to resolve it.")
        case .preferUserChanges:
            String(localized: "Automatically merges changes and uses your draft for conflicting fields. External edits to those fields may be overwritten; other disk changes are kept.")
        case .preferDiskChanges:
            String(localized: "Automatically merges changes and keeps the disk values for conflicting fields. Your edits to those fields are discarded, and the save report lists them.")
        case .requireReload:
            String(localized: "Stops saving whenever the file revision changes. Your draft is kept. Use Reload from Disk in the file menu before editing again, then reopen Metadata Editor if it is open.")
        }
    }
}
