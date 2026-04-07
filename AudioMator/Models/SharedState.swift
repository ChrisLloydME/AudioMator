import Combine
import Foundation

final class SharedState: ObservableObject {
    private static let visibleMiddleListColumnsDefaultsKey = "middleList.visibleColumns"
    private static let visibleToolbarButtonsDefaultsKey = "toolbar.visibleButtons"

    @Published var selectedSidebarItem: SidebarSelection? = .quickImport
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []

    // Custom ordering for the middle list (session-only)
    @Published var customOrder: [AudioFile.ID] = []

    @Published var visibleMiddleListColumns: Set<MiddleListColumn> {
        didSet {
            let fallbackColumns = Set(MiddleListColumn.defaultVisibleColumns)
            let normalizedColumns = visibleMiddleListColumns.isEmpty ? fallbackColumns : visibleMiddleListColumns

            guard normalizedColumns == visibleMiddleListColumns else {
                visibleMiddleListColumns = normalizedColumns
                return
            }

            UserDefaults.standard.set(
                MiddleListColumn.allCases
                    .filter(normalizedColumns.contains)
                    .map(\.rawValue),
                forKey: Self.visibleMiddleListColumnsDefaultsKey
            )
        }
    }

    @Published var visibleToolbarButtons: Set<ToolbarButtonOption> {
        didSet {
            UserDefaults.standard.set(
                ToolbarButtonOption.allCases
                    .filter(visibleToolbarButtons.contains)
                    .map(\.rawValue),
                forKey: Self.visibleToolbarButtonsDefaultsKey
            )
        }
    }

    init() {
        let storedColumns = UserDefaults.standard
            .stringArray(forKey: Self.visibleMiddleListColumnsDefaultsKey)?
            .compactMap(MiddleListColumn.init(rawValue:))
        let storedToolbarButtons = UserDefaults.standard
            .stringArray(forKey: Self.visibleToolbarButtonsDefaultsKey)?
            .compactMap(ToolbarButtonOption.init(rawValue:))
        let fallbackColumns = Set(MiddleListColumn.defaultVisibleColumns)
        let fallbackToolbarButtons = Set(ToolbarButtonOption.defaultVisibleButtons)
        self.visibleMiddleListColumns = storedColumns.map(Set.init) ?? fallbackColumns
        self.visibleToolbarButtons = storedToolbarButtons.map(Set.init) ?? fallbackToolbarButtons

        if visibleMiddleListColumns.isEmpty {
            visibleMiddleListColumns = fallbackColumns
        }
    }

    var currentFileSourceMode: FileSourceMode {
        (selectedSidebarItem ?? .quickImport).sourceMode
    }
}
