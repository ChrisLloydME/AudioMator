#if os(macOS)
import SwiftUI

struct ViewLayoutCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button {
                NotificationCenter.default.post(name: .requestToggleInspector, object: nil)
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }
}
#endif
