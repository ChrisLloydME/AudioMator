#if os(macOS)
import SwiftUI

struct AppInfoCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                UserDefaults.standard.set(AppSettingsTab.about.rawValue, forKey: settingsSelectedTabDefaultsKey)
                openSettings()
            } label: {
                Label("About AudioMator", systemImage: "info.circle")
            }
        }
    }
}
#endif
