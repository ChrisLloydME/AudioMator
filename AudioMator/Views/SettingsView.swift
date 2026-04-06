import AppKit
import SwiftUI

let settingsSelectedTabDefaultsKey = "settings.selectedTab"

enum AppSettingsTab: String, Hashable {
    case general
    case toolbar
    case columns
    case about
}

struct SettingsView: View {
    @ObservedObject var sharedState: SharedState

    @AppStorage("hasCompletedWelcomeSplash") private var hasCompletedWelcomeSplash: Bool = false
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
            get: { !hasCompletedWelcomeSplash },
            set: { hasCompletedWelcomeSplash = !$0 }
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

        if !copyright.isEmpty {
            return "\(copyright) AudioMator includes third-party open-source software. See Acknowledgements."
        }

        return "Copyright © 2025-2026 Christopher Lloyd. All rights reserved. AudioMator includes third-party open-source software. See Acknowledgements."
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

    private func isLastVisibleColumn(_ column: MiddleListColumn) -> Bool {
        sharedState.visibleMiddleListColumns.contains(column)
            && sharedState.visibleMiddleListColumns.count == 1
    }
}

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AboutSettingsTab: View {
    let appDisplayName: String
    let shortVersionString: String
    let buildNumber: String
    let aboutDescription: String

    @State private var isAcknowledgementsPresented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(alignment: .center, spacing: 36) {
                AboutAppIconView()

                VStack(alignment: .leading, spacing: 8) {
                    Text(appDisplayName)
                        .font(.system(size: 48, weight: .regular))

                    Text("Version \(shortVersionString)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Build \(buildNumber)")
                        .font(.headline)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            Text(aboutDescription)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()

                Button("Acknowledgements…") {
                    isAcknowledgementsPresented = true
                }
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isAcknowledgementsPresented) {
            AcknowledgementsSheet()
        }
    }
}

private struct AboutAppIconView: View {
    var body: some View {
        Image(nsImage: applicationIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 180, height: 180)
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var applicationIcon: NSImage {
        NSApp.applicationIconImage
    }
}

private struct AcknowledgementsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let acknowledgements: [(title: String, detail: String)] = [
        (
            title: "TagLib",
            detail: "AudioMator includes a bundled TagLib bridge for metadata reading and writing. TagLib is third-party open-source software and remains subject to its own LGPL/MPL licensing terms."
        ),
        (
            title: "MusicBrainz",
            detail: "The optional MusicBrainz Browser uses MusicBrainz web services and metadata for search and reference workflows. AudioMator's client integration is original code, while MusicBrainz data and services remain subject to MusicBrainz licensing and usage terms."
        ),
        (
            title: "AVFoundation",
            detail: "Apple media frameworks provide supplemental metadata inspection and audio property information."
        ),
        (
            title: "SwiftUI and AppKit",
            detail: "The macOS interface, commands, windows, and settings experience are built with Apple's native UI frameworks."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Acknowledgements")
                .font(.title2.weight(.semibold))

            Text("AudioMator builds on the following frameworks and services.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(acknowledgements, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)

                            Text(item.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 360)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(sharedState: SharedState())
    }
}
