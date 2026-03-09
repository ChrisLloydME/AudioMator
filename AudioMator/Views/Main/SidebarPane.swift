import SwiftUI

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
