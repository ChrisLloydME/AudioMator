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
    @State private var isReleaseNotesPresented: Bool = false

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

                Button("Release Notes…") {
                    isReleaseNotesPresented = true
                }
                .controlSize(.large)

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
        .sheet(isPresented: $isReleaseNotesPresented) {
            ReleaseNotesSheet()
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
            detail: "AudioMator includes a bundled TagLib bridge for metadata reading and writing. TagLib is distributed under the GNU Lesser General Public License (LGPL) and Mozilla Public License (MPL). "
        ),
        (
            title: "iTunes-Artwork-Finder by bendodson",
            detail: "AudioMator's iTunes artwork implementation is fully written in Swift, but the lookup approach and method design were informed by iTunes-Artwork-Finder by bendodson."
        ),
        (
            title: "MusicBrainz",
            detail: "The optional MusicBrainz Browser uses MusicBrainz web services and metadata for search and reference workflows. AudioMator's client integration is original code, while MusicBrainz data and services remain subject to MusicBrainz licensing and usage terms."
        ),
        (
            title: "Privacy & Network Activity",
            detail: """
            AudioMator performs optional network requests only for online features: 
            1. iTunes artwork lookup to itunes.apple.com (search/lookup), with query terms from metadata such as iTunes Album ID, album name, or track title; artwork downloads then come from Apple CDN hosts (is5-ssl.mzstatic.com / a5.mzstatic.com). 
            2. MusicBrainz Browser requests to musicbrainz.org/ws/2, using search metadata fields such as title, artist, album, album artist, track number, track total, duration bucket, release year/date, ISRC, barcode, and MusicBrainz IDs (or IDs parsed from a pasted MusicBrainz link). 
            3. Release Notes loading requests GitHub release data from api.github.com. Audio files themselves are never uploaded.
            """
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
        .frame(width: 560, height: 460)
    }
}

private struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var loadState: LoadState = .loading

    private let client = GitHubReleaseNotesClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Release Notes")
                .font(.title2.weight(.semibold))

            Text("Recent published changes for AudioMator.")
                .foregroundStyle(.secondary)

            content

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 430)
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
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
