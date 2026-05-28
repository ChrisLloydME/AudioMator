import SwiftUI

let settingsSelectedTabDefaultsKey = "settings.selectedTab"

enum AppSettingsTab: String, Hashable {
    case general
    case toolbar
    case columns
    case inspector
    case about
}

private func formattedAboutDescription(copyright: String) -> String {
    let trimmedCopyright = copyright.trimmingCharacters(in: .whitespacesAndNewlines)

    if !trimmedCopyright.isEmpty {
        let copyrightSentence = trimmedCopyright.hasSuffix(".") ? trimmedCopyright : "\(trimmedCopyright)."
        return "\(copyrightSentence) AudioMator includes third-party open-source software. See Acknowledgements."
    }

    return "Copyright © 2025-2026 Christopher Lloyd. AudioMator includes third-party open-source software. See Acknowledgements."
}

struct SettingsView: View {
    @ObservedObject var sharedState: SharedState

    @AppStorage(WelcomeSplashProgress.completionKey) private var hasCompletedWelcomeSplash: Bool = false
    @AppStorage(WelcomeSplashProgress.completedVersionKey) private var completedWelcomeSplashVersion: Int = 0
    @AppStorage("suppressesUnsavedInspectorDiscardWarning") private var suppressesUnsavedInspectorDiscardWarning: Bool = false
    @AppStorage(settingsSelectedTabDefaultsKey) private var selectedTabRawValue: String = AppSettingsTab.general.rawValue

    var body: some View {
        TabView(selection: selectedTabBinding) {
            GeneralSettingsTab(
                showWelcomeScreenOnLaunch: showWelcomeScreenOnLaunchBinding,
                warnBeforeDiscardingInspectorEdits: warnBeforeDiscardingInspectorEditsBinding,
                onShowWelcomeScreen: showWelcomeScreen
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(AppSettingsTab.general)

            ToolbarSettingsTab(
                sharedState: sharedState,
                toolbarButtonVisibilityBinding: toolbarButtonVisibilityBinding(for:)
            )
            .tabItem {
                Label("Toolbar", systemImage: "switch.2")
            }
            .tag(AppSettingsTab.toolbar)

            ColumnVisibilitySettingsTab(
                sharedState: sharedState,
                columnVisibilityBinding: columnVisibilityBinding(for:),
                isLastVisibleColumn: isLastVisibleColumn
            )
            .tabItem {
                Label("Columns", systemImage: "rectangle.split.3x1")
            }
            .tag(AppSettingsTab.columns)

            InspectorSettingsTab(
                sharedState: sharedState,
                metadataFieldVisibilityBinding: metadataFieldVisibilityBinding(for:),
                isLastVisibleMetadataField: isLastVisibleMetadataField
            )
            .tabItem {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .tag(AppSettingsTab.inspector)

            AboutSettingsTab(
                appDisplayName: appDisplayName,
                shortVersionString: shortVersionString,
                buildNumber: buildNumber,
                aboutDescription: aboutDescription
            )
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
            .tag(AppSettingsTab.about)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var selectedTabBinding: Binding<AppSettingsTab> {
        Binding(
            get: { AppSettingsTab(rawValue: selectedTabRawValue) ?? .general },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    private var showWelcomeScreenOnLaunchBinding: Binding<Bool> {
        Binding(
            get: {
                WelcomeSplashProgress.shouldPresent(
                    hasCompleted: hasCompletedWelcomeSplash,
                    completedVersion: completedWelcomeSplashVersion
                )
            },
            set: { shouldShowOnLaunch in
                hasCompletedWelcomeSplash = !shouldShowOnLaunch
                completedWelcomeSplashVersion = shouldShowOnLaunch ? 0 : WelcomeSplashProgress.currentVersion
            }
        )
    }

    private var warnBeforeDiscardingInspectorEditsBinding: Binding<Bool> {
        Binding(
            get: { !suppressesUnsavedInspectorDiscardWarning },
            set: { suppressesUnsavedInspectorDiscardWarning = !$0 }
        )
    }

    private func showWelcomeScreen() {
        NotificationCenter.default.post(name: .showWelcomeSplash, object: nil)
    }

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "AudioMator"
    }

    private var shortVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
    }

    private var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown"
    }

    private var aboutDescription: String {
        let copyright = (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return formattedAboutDescription(copyright: copyright)
    }

    private func columnVisibilityBinding(for column: MiddleListColumn) -> Binding<Bool> {
        Binding(
            get: { sharedState.visibleMiddleListColumns.contains(column) },
            set: { isVisible in
                var updatedColumns = sharedState.visibleMiddleListColumns

                if isVisible {
                    updatedColumns.insert(column)
                } else if updatedColumns.count > 1 {
                    updatedColumns.remove(column)
                }

                sharedState.visibleMiddleListColumns = updatedColumns
            }
        )
    }

    private func toolbarButtonVisibilityBinding(for button: ToolbarButtonOption) -> Binding<Bool> {
        Binding(
            get: { sharedState.visibleToolbarButtons.contains(button) },
            set: { isVisible in
                var updatedButtons = sharedState.visibleToolbarButtons

                if isVisible {
                    updatedButtons.insert(button)
                } else {
                    updatedButtons.remove(button)
                }

                sharedState.visibleToolbarButtons = updatedButtons
            }
        )
    }

    private func metadataFieldVisibilityBinding(for field: InspectorMetadataField) -> Binding<Bool> {
        Binding(
            get: { sharedState.visibleInspectorMetadataFields.contains(field) },
            set: { isVisible in
                var updatedFields = sharedState.visibleInspectorMetadataFields

                if isVisible {
                    updatedFields.insert(field)
                } else if updatedFields.count > 1 {
                    updatedFields.remove(field)
                }

                sharedState.visibleInspectorMetadataFields = updatedFields
            }
        )
    }

    private func isLastVisibleColumn(_ column: MiddleListColumn) -> Bool {
        sharedState.visibleMiddleListColumns.contains(column)
            && sharedState.visibleMiddleListColumns.count == 1
    }

    private func isLastVisibleMetadataField(_ field: InspectorMetadataField) -> Bool {
        sharedState.visibleInspectorMetadataFields.contains(field)
            && sharedState.visibleInspectorMetadataFields.count == 1
    }
}

#if os(iOS)
private enum IPadSettingsTab: String, Hashable {
    case leftList
    case about
}

struct IPadSettingsView: View {
    @ObservedObject var sharedState: SharedState

    @AppStorage("ipad.settings.selectedTab") private var selectedTabRawValue: String = IPadSettingsTab.leftList.rawValue

    var body: some View {
        TabView(selection: selectedTabBinding) {
            IPadLeftListMetadataSettingsTab(sharedState: sharedState)
                .tabItem {
                    Label("List", systemImage: "list.bullet.rectangle")
                }
                .tag(IPadSettingsTab.leftList)

            AboutSettingsTab(
                appDisplayName: appDisplayName,
                shortVersionString: shortVersionString,
                buildNumber: buildNumber,
                aboutDescription: aboutDescription
            )
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
            .tag(IPadSettingsTab.about)
        }
        .frame(minWidth: 540, minHeight: 520)
    }

    private var selectedTabBinding: Binding<IPadSettingsTab> {
        Binding(
            get: { IPadSettingsTab(rawValue: selectedTabRawValue) ?? .leftList },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "AudioMator"
    }

    private var shortVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
    }

    private var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown"
    }

    private var aboutDescription: String {
        let copyright = (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return formattedAboutDescription(copyright: copyright)
    }
}

private struct IPadLeftListMetadataSettingsTab: View {
    @ObservedObject var sharedState: SharedState

    var body: some View {
        List {
            Section {
                IPadLeftListMetadataPreviewRow(
                    fields: SharedState.normalizedIPadLeftListMetadataFields(sharedState.iPadLeftListMetadataFields)
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("Preview")
            }

            Section {
                ForEach(0..<IPadLeftListMetadataField.defaultConfiguration.count, id: \.self) { index in
                    Picker("Field \(index + 1)", selection: metadataFieldBinding(at: index)) {
                        ForEach(IPadLeftListMetadataField.allCases) { field in
                            Text(field.displayName)
                                .tag(field)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Left List Metadata Fields")
            } footer: {
                Text("Fields 1-2 and 5-6 appear on the left side of the two metadata rows. Fields 3-4 and 7-8 appear on the right side.")
            }

            Section {
                Button("Restore Default Metadata Fields") {
                    sharedState.iPadLeftListMetadataFields = IPadLeftListMetadataField.defaultConfiguration
                }
            }
        }
        .iPadRoundedGroupedListStyle()
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func metadataFieldBinding(at index: Int) -> Binding<IPadLeftListMetadataField> {
        Binding(
            get: {
                let fields = SharedState.normalizedIPadLeftListMetadataFields(sharedState.iPadLeftListMetadataFields)
                return fields[index]
            },
            set: { field in
                var fields = SharedState.normalizedIPadLeftListMetadataFields(sharedState.iPadLeftListMetadataFields)
                fields[index] = field
                sharedState.iPadLeftListMetadataFields = fields
            }
        )
    }
}

private struct IPadLeftListMetadataPreviewRow: View {
    let fields: [IPadLeftListMetadataField]

    private var normalizedFields: [IPadLeftListMetadataField] {
        SharedState.normalizedIPadLeftListMetadataFields(fields)
    }

    var body: some View {
        HStack(spacing: 12) {
            artworkPlaceholder

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                metadataRow(leftPositions: [0, 1], rightPositions: [2, 3])
                metadataRow(leftPositions: [4, 5], rightPositions: [6, 7])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func metadataRow(leftPositions: [Int], rightPositions: [Int]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            metadataGroupText(for: leftPositions, alignment: .leading)

            Spacer(minLength: 16)

            metadataGroupText(for: rightPositions, alignment: .trailing)
        }
    }

    private func metadataGroupText(for positions: [Int], alignment: TextAlignment) -> some View {
        Text(fieldNames(for: positions))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(alignment)
            .lineLimit(1)
    }

    private func fieldNames(for positions: [Int]) -> String {
        positions
            .compactMap { position -> String? in
                guard normalizedFields.indices.contains(position) else { return nil }
                return normalizedFields[position].displayName
            }
            .joined(separator: " · ")
    }

    private var artworkPlaceholder: some View {
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
#endif

private struct GeneralSettingsTab: View {
    @Binding var showWelcomeScreenOnLaunch: Bool
    @Binding var warnBeforeDiscardingInspectorEdits: Bool
    let onShowWelcomeScreen: () -> Void

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Show Welcome Screen on Launch", isOn: $showWelcomeScreenOnLaunch)

                Button("Show Welcome Screen Now", action: onShowWelcomeScreen)
            }

            Section("Editing") {
                Toggle(
                    "Warn Before Discarding Unsaved Inspector Edits",
                    isOn: $warnBeforeDiscardingInspectorEdits
                )
            }
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ColumnVisibilitySettingsTab: View {
    @ObservedObject var sharedState: SharedState
    let columnVisibilityBinding: (MiddleListColumn) -> Binding<Bool>
    let isLastVisibleColumn: (MiddleListColumn) -> Bool

    private let columnGridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 220), alignment: .leading),
        GridItem(.flexible(minimum: 220), alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Middle List Columns")
                        .font(.title3.weight(.semibold))

                    Text("Choose which columns appear in the main track list.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columnGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(MiddleListColumn.allCases) { column in
                        Toggle(column.displayName, isOn: columnVisibilityBinding(column))
                            .disabled(isLastVisibleColumn(column))
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Button("Restore Default Columns") {
                        sharedState.visibleMiddleListColumns = Set(MiddleListColumn.defaultVisibleColumns)
                    }

                    Text("Changes apply immediately. At least one column must remain visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ToolbarSettingsTab: View {
    @ObservedObject var sharedState: SharedState
    let toolbarButtonVisibilityBinding: (ToolbarButtonOption) -> Binding<Bool>

    private let buttonGridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 220), alignment: .leading),
        GridItem(.flexible(minimum: 220), alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toolbar Buttons")
                        .font(.title3.weight(.semibold))

                    Text("Choose which actions appear in the main window toolbar.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: buttonGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(ToolbarButtonOption.allCases) { button in
                        Toggle(button.displayName, isOn: toolbarButtonVisibilityBinding(button))
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Button("Restore Default Buttons") {
                        sharedState.visibleToolbarButtons = Set(ToolbarButtonOption.defaultVisibleButtons)
                    }

                    Text("Changes apply immediately in the main window toolbar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InspectorSettingsTab: View {
    @ObservedObject var sharedState: SharedState
    let metadataFieldVisibilityBinding: (InspectorMetadataField) -> Binding<Bool>
    let isLastVisibleMetadataField: (InspectorMetadataField) -> Bool

    private let fieldGridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 220), alignment: .leading),
        GridItem(.flexible(minimum: 220), alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspector Metadata Fields")
                        .font(.title3.weight(.semibold))

                    Text("Choose which metadata fields appear in the right inspector.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: fieldGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(InspectorMetadataField.allCases) { field in
                        Toggle(field.displayName, isOn: metadataFieldVisibilityBinding(field))
                            .disabled(isLastVisibleMetadataField(field))
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Button("Restore Default Metadata Fields") {
                        sharedState.visibleInspectorMetadataFields = Set(InspectorMetadataField.defaultVisibleFields)
                    }

                    Text("Changes apply immediately. At least one metadata field must remain visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AboutSettingsTab: View {
    let appDisplayName: String
    let shortVersionString: String
    let buildNumber: String
    let aboutDescription: String
    private let contactEmail = "AudioMator@lloydME.com"

    @State private var isAcknowledgementsPresented: Bool = false
    @State private var isPrivacyPresented: Bool = false
    @State private var isReleaseNotesPresented: Bool = false

    var body: some View {
        #if os(iOS)
        List {
            Section {
                IPadAboutHeroCard(
                    title: "AudioMator",
                    copyrightText: copyrightText,
                    contactEmail: contactEmail
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                AboutNavigationRow("Release Notes…") {
                    isReleaseNotesPresented = true
                }

                AboutNavigationRow("Acknowledgements…") {
                    isAcknowledgementsPresented = true
                }

                AboutNavigationRow("Privacy…") {
                    isPrivacyPresented = true
                }
            }
        }
        .iPadRoundedGroupedListStyle()
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isAcknowledgementsPresented) {
            IPadDismissibleSheet(title: "Acknowledgements") {
                AcknowledgementsSheet()
            }
        }
        .sheet(isPresented: $isPrivacyPresented) {
            IPadDismissibleSheet(title: "Privacy") {
                PrivacySheet()
            }
        }
        .sheet(isPresented: $isReleaseNotesPresented) {
            IPadDismissibleSheet(title: "Release Notes") {
                ReleaseNotesSheet()
            }
        }
        #else
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            HStack(alignment: .center, spacing: 34) {
                AboutAppIconView(size: 164)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appDisplayName)
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        HStack(spacing: 14) {
                            Text("Version \(shortVersionString)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("Build \(buildNumber)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text(aboutDescription)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                        Label(contactEmail, systemImage: "envelope")
                            .font(.headline)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: -36)

            Spacer()

            HStack {
                Spacer()

                Button("Release Notes…") {
                    isReleaseNotesPresented = true
                }
                .controlSize(.large)

                Button("Acknowledgements…") {
                    isAcknowledgementsPresented = true
                }
                .controlSize(.large)

                Button("Privacy…") {
                    isPrivacyPresented = true
                }
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isAcknowledgementsPresented) {
            AcknowledgementsSheet()
        }
        .sheet(isPresented: $isPrivacyPresented) {
            PrivacySheet()
        }
        .sheet(isPresented: $isReleaseNotesPresented) {
            ReleaseNotesSheet()
        }
        #endif
    }

    private var copyrightText: String {
        let copyright = (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !copyright.isEmpty {
            return copyright
        }

        return "Copyright © 2025-2026 Christopher Lloyd"
    }
}

#if os(iOS)
private struct IPadAboutHeroCard: View {
    let title: String
    let copyrightText: String
    let contactEmail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("AppIconPreview")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(copyrightText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                    Label(contactEmail, systemImage: "envelope")
                        .font(.body.weight(.medium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 1)
        }
    }
}

private struct AboutNavigationRow: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.replacingOccurrences(of: "…", with: ""))
    }
}
#endif

private struct AboutAppIconView: View {
    let size: CGFloat

    init(size: CGFloat = 180) {
        self.size = size
    }

    var body: some View {
        if let applicationIcon = PlatformApplication.appIconImage {
            Image(platformImage: applicationIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

private struct AcknowledgementsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let acknowledgements: [(title: String, details: [String])] = [
        (
            title: "TagLib",
            details: [
                "Project: https://github.com/taglib/taglib",
                "Website: https://taglib.org/",
                "AudioMator uses TagLib through the local bridge for metadata reading and writing.",
                "AudioMator includes a local copy of TagLib source code in the project and uses it directly through the bundled bridge.",
                "This bundled copy has been trimmed for AudioMator's needs, including removal of files that are not required by this app.",
                "TagLib is distributed under the GNU Lesser General Public License (LGPL) and Mozilla Public License (MPL). AudioMator distributes the relevant TagLib license texts with the app."
            ]
        ),
        (
            title: "Sparkle",
            details: [
                "Project: https://github.com/sparkle-project/Sparkle",
                "Website: https://sparkle-project.org/",
                "AudioMator keeps Sparkle update infrastructure available for macOS, but update checking is currently disabled and Sparkle is not linked into the app by default."
            ]
        ),
        (
            title: "Apple iTunes Search API",
            details: [
                "Service documentation: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/",
                "AudioMator uses the public iTunes Search API to search Apple catalog metadata, inspect album/track results, and prepare selected tag values for local audio files.",
                "AudioMator can also use iTunes lookup results to find and download album artwork candidates from Apple artwork CDN endpoints."
            ]
        ),
        (
            title: "iTunes-Artwork-Finder by bendodson",
            details: [
                "Project: https://github.com/bendodson/itunes-artwork-finder",
                "AudioMator's artwork implementation is fully rewritten in Swift, but the original artwork lookup method and approach were based on the ideas from this project."
            ]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Acknowledgements")
                    .font(.title2.weight(.semibold))

                Text("AudioMator builds on the following third-party projects and ideas.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                #if os(iOS)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(acknowledgements, id: \.title) { item in
                        IPadRoundedRowGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(.headline)

                                ForEach(item.details, id: \.self) { detail in
                                    Text(detail)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                #else
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(acknowledgements, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)

                            ForEach(item.details, id: \.self) { detail in
                                Text(detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                #endif
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 560, height: 460)
        #endif
    }
}

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    private var sections: [(title: String, details: [String])] {
        [
            (
                title: "Overview",
                details: [
                    "AudioMator's local metadata reading and writing runs on your Mac.",
                    "Your music files themselves are not uploaded."
                ]
            ),
            (
                title: "iTunes Search API and artwork lookup",
                details: [
                    "Target hosts: \(NetworkServiceDisclosure.ITunesArtwork.domains.joined(separator: ", "))",
                    NetworkServiceDisclosure.ITunesArtwork.sentDataSummary,
                    "Purpose: searching Apple catalog metadata, reviewing album and track results, preparing selected metadata writes, previewing artwork, downloading selected artwork, and applying chosen values locally."
                ]
            ),
            (
                title: "MusicBrainz browser and search",
                details: [
                    "Target host: \(NetworkServiceDisclosure.MusicBrainz.domains.joined(separator: ", ")) (/ws/2 API and selected MusicBrainz pages)",
                    NetworkServiceDisclosure.MusicBrainz.sentDataSummary,
                    "Purpose: searching, reviewing, and applying MusicBrainz metadata."
                ]
            ),
            (
                title: "Release notes",
                details: [
                    "Target host: \(NetworkServiceDisclosure.ReleaseNotes.host)",
                    "Sent data: request headers and the release list request only. No audio file content is sent.",
                    "Purpose: loading published release notes for AudioMator."
                ]
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.title2.weight(.semibold))

                Text("Network activity only happens when optional online features are used.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                #if os(iOS)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.title) { section in
                        IPadRoundedRowGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.headline)

                                ForEach(section.details, id: \.self) { detail in
                                    Text(detail)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                #else
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)

                            ForEach(section.details, id: \.self) { detail in
                                Text(detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                #endif
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 580, height: 500)
        #endif
    }
}

private struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var loadState: LoadState = .loading

    private let client = GitHubReleaseNotesClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Release Notes")
                    .font(.title2.weight(.semibold))

                Text("Recent published changes for AudioMator.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            content
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    HStack {
                        Spacer()

                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 640, height: 430)
        #endif
        .task {
            await loadReleaseNotes()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading release notes…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Release Notes",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )

        case .loaded(let releases):
            if releases.isEmpty {
                ContentUnavailableView(
                    "No Release Notes",
                    systemImage: "doc.text",
                    description: Text("No public releases are available yet.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(releases) { release in
                            ReleaseNoteCard(release: release)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .audiomatorScrollEdgeEffect(.soft, for: .vertical)
            }
        }
    }

    private func loadReleaseNotes() async {
        await MainActor.run {
            loadState = .loading
        }

        do {
            let releases = try await client.fetchReleases()
            await MainActor.run {
                loadState = .loaded(releases)
            }
        } catch {
            await MainActor.run {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    private enum LoadState {
        case loading
        case loaded([GitHubReleaseNote])
        case failed(String)
    }
}

private struct ReleaseNoteCard: View {
    let release: GitHubReleaseNote

    private static let publishedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(release.displayTitle)
                    .font(.title3.weight(.semibold))

                Text(release.tagName)
                    .font(.subheadline)
                    .monospaced()
                    .foregroundStyle(.secondary)

                if release.isPrerelease {
                    Text("Pre-release")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()

                if let publishedAt = release.publishedAt {
                    Text(Self.publishedDateFormatter.string(from: publishedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ReleaseMarkdownText(markdown: release.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .iPadRoundedGroupedSurface()
        #else
        .background(Color(platformColor: .audiomatorControlBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }
}

private struct ReleaseMarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .spacer:
                    Color.clear
                        .frame(height: 4)

                case .heading(let level, let text):
                    inlineText(text)
                        .font(headingFont(for: level))
                        .padding(.top, level == 1 ? 4 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                case .bullet(let indentLevel, let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)

                        inlineText(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indentLevel) * 18)

                case .paragraph(let indentLevel, let text):
                    inlineText(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, CGFloat(indentLevel) * 18)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderedBlocks: [ReleaseMarkdownBlock] {
        ReleaseMarkdownBlock.parse(markdown)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.semibold)
        case 2:
            return .headline.weight(.semibold)
        default:
            return .body.weight(.semibold)
        }
    }

    private func inlineText(_ text: String) -> Text {
        let source = text.isEmpty ? "No release notes provided." : text

        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }

        return Text(verbatim: source)
    }
}

private enum ReleaseMarkdownBlock {
    case spacer
    case heading(level: Int, text: String)
    case bullet(indentLevel: Int, text: String)
    case paragraph(indentLevel: Int, text: String)

    static func parse(_ markdown: String) -> [ReleaseMarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else {
            return [.paragraph(indentLevel: 0, text: "No release notes provided.")]
        }

        var blocks: [ReleaseMarkdownBlock] = []

        for line in lines {
            let rawLine = String(line)
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if blocks.last.map({ if case .spacer = $0 { return true } else { return false } }) != true {
                    blocks.append(.spacer)
                }
                continue
            }

            let leadingWhitespaceCount = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let indentLevel = max(0, leadingWhitespaceCount / 2)

            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let bulletText = bulletText(from: trimmed) {
                blocks.append(.bullet(indentLevel: indentLevel, text: bulletText))
                continue
            }

            blocks.append(.paragraph(indentLevel: indentLevel, text: trimmed))
        }

        return blocks.isEmpty ? [.paragraph(indentLevel: 0, text: "No release notes provided.")] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count

        guard level > 0, level <= 6 else { return nil }

        let remainder = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        return (level, remainder)
    }

    private static func bulletText(from line: String) -> String? {
        guard line.count >= 2 else { return nil }

        let marker = line.prefix(2)
        guard marker == "- " || marker == "* " || marker == "+ " else { return nil }

        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(sharedState: SharedState())
    }
}
