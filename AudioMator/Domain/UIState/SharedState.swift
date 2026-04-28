import Combine
import Foundation

struct MiddleListSort: Equatable {
    let column: MiddleListColumn
    let ascending: Bool
}

final class SharedState: ObservableObject {
    private static let visibleMiddleListColumnsDefaultsKey = "middleList.visibleColumns"
    private static let visibleToolbarButtonsDefaultsKey = "toolbar.visibleButtons"
    private static let middleListSortColumnDefaultsKey = "middleList.sort.column"
    private static let middleListSortAscendingDefaultsKey = "middleList.sort.ascending"

    @Published var selectedSidebarItem: SidebarSelection? = .quickImport
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []

    // Custom ordering for the middle list (session-only)
    @Published var customOrder: [AudioFile.ID] = []

    @Published var middleListSort: MiddleListSort? {
        didSet {
            let defaults = UserDefaults.standard
            if let middleListSort {
                defaults.set(middleListSort.column.rawValue, forKey: Self.middleListSortColumnDefaultsKey)
                defaults.set(middleListSort.ascending, forKey: Self.middleListSortAscendingDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.middleListSortColumnDefaultsKey)
                defaults.removeObject(forKey: Self.middleListSortAscendingDefaultsKey)
            }
        }
    }

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
        let storedSort = UserDefaults.standard
            .string(forKey: Self.middleListSortColumnDefaultsKey)
            .flatMap(MiddleListColumn.init(rawValue:))
            .map { MiddleListSort(
                column: $0,
                ascending: UserDefaults.standard.object(forKey: Self.middleListSortAscendingDefaultsKey) as? Bool ?? true
            ) }
        let fallbackColumns = Set(MiddleListColumn.defaultVisibleColumns)
        let fallbackToolbarButtons = Set(ToolbarButtonOption.defaultVisibleButtons)
        self.visibleMiddleListColumns = storedColumns.map(Set.init) ?? fallbackColumns
        self.visibleToolbarButtons = storedToolbarButtons.map(Set.init) ?? fallbackToolbarButtons
        self.middleListSort = storedSort

        if visibleMiddleListColumns.isEmpty {
            visibleMiddleListColumns = fallbackColumns
        }
    }

    var currentFileSourceMode: FileSourceMode {
        (selectedSidebarItem ?? .quickImport).sourceMode
    }

    func orderedMiddleListFiles(from files: [AudioFile]) -> [AudioFile] {
        let manuallyOrderedFiles = manualMiddleListFiles(from: files)
        guard let middleListSort else { return manuallyOrderedFiles }

        return manuallyOrderedFiles.enumerated().sorted { lhs, rhs in
            let comparison = middleListSort.column.compare(lhs.element, rhs.element)
            guard comparison != .orderedSame else {
                return lhs.offset < rhs.offset
            }

            if middleListSort.ascending {
                return comparison == .orderedAscending
            }
            return comparison == .orderedDescending
        }
        .map(\.element)
    }

    func orderedMiddleListIDs(from files: [AudioFile]) -> [AudioFile.ID] {
        orderedMiddleListFiles(from: files).map(\.id)
    }

    private func manualMiddleListFiles(from files: [AudioFile]) -> [AudioFile] {
        guard !customOrder.isEmpty else { return files }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var orderedFiles: [AudioFile] = []
        orderedFiles.reserveCapacity(files.count)

        for id in customOrder {
            if let file = filesByID[id] {
                orderedFiles.append(file)
            }
        }

        let existingIDs = Set(orderedFiles.map(\.id))
        for file in files where !existingIDs.contains(file.id) {
            orderedFiles.append(file)
        }

        return orderedFiles
    }
}
