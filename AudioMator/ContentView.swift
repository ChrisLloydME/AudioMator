import SwiftUI
import Combine
import AppKit

// MARK: - Shared state

final class SharedState: ObservableObject {
    @Published var selectedSidebarItem: String? = "all"
    @Published var selectedAudioID: AudioFile.ID?
}

// MARK: - Root ContentView (pure SwiftUI A-style)

struct ContentView: View {
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var state = SharedState()

    var body: some View {
        NavigationSplitView {
            SidebarPane(state: state)
        } content: {
            ContentPane(viewModel: viewModel, state: state)
        } detail: {
            InspectorPane(viewModel: viewModel, state: state)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.addFiles()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: Sidebar

struct SidebarPane: View {
    @ObservedObject var state: SharedState

    var body: some View {
        List(selection: $state.selectedSidebarItem) {
            Section("Library") {
                Text("All Audio")
                    .tag("all" as String?)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: Content (Center)

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    var body: some View {
        Group {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    "没有音频文件",
                    systemImage: "music.note.list",
                    description: Text("点击右上角添加按钮导入音频文件")
                )
            } else {
                Table(
                    viewModel.files,
                    selection: Binding(
                        get: { state.selectedAudioID },
                        set: { state.selectedAudioID = $0 }
                    )
                ) {
                    TableColumn("文件名") { file in
                        Text(file.url.lastPathComponent)
                    }
                    TableColumn("标题") { file in
                        Text(file.title ?? "—")
                    }
                    TableColumn("艺术家") { file in
                        Text(file.artist ?? "—")
                    }
                    TableColumn("专辑") { file in
                        Text(file.album ?? "—")
                    }
                }
            }
        }
    }
}

// MARK: Inspector (Right Pane)

struct InspectorPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    var body: some View {
        Group {
            if let id = state.selectedAudioID,
               let file = viewModel.files.first(where: { $0.id == id }) {

                Form {
                    Section("文件") {
                        Text(file.url.lastPathComponent)
                    }

                    Section("元数据") {
                        LabeledContent("标题") { Text(file.title ?? "—") }
                        LabeledContent("艺术家") { Text(file.artist ?? "—") }
                        LabeledContent("专辑") { Text(file.album ?? "—") }
                    }
                }
                .formStyle(.grouped)

            } else {
                ContentUnavailableView(
                    "选择一个音频文件",
                    systemImage: "music.quarternote.3"
                )
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

#Preview {
    ContentView()
}
