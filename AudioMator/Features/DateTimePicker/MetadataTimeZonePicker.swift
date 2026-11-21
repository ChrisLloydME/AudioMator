import SwiftUI

struct MetadataTimeZonePicker: View {
    let current: TimeZone
    let reference: Date
    let onSelection: (String) -> Bool

    var body: some View {
        MacSearchDropdownField(
            text: Self.displayName(for: current, at: reference),
            placeholder: String(localized: "Search time zones"),
            accessibilityLabel: String(localized: "Time Zone"),
            restoresTextOnDismiss: true,
            minimumDropdownWidth: 0,
            suggestions: { query in
                Self.options(matching: query, current: current).map { option in
                    .init(
                        id: option.id,
                        title: option.name,
                        detail: "\(option.id) · \(Self.offset(for: option.zone, at: reference))",
                        selectionText: Self.displayName(for: option.zone, at: reference)
                    )
                }
            },
            onSelect: { onSelection($0.id) }
        )
        .frame(height: 24)
    }

    static func displayName(for zone: TimeZone, at date: Date) -> String {
        if zone.identifier == TimeZone.gmt.identifier { return "UTC" }
        return "\(option(for: zone).name) (\(offset(for: zone, at: date)))"
    }

    private static func offset(for zone: TimeZone, at date: Date) -> String {
        MetadataDSTResolutionOption.formatGMTOffset(seconds: zone.secondsFromGMT(for: date))
    }

    struct Option: Identifiable {
        let zone: TimeZone
        let name: String
        let searchIndex: String

        var id: String { zone.identifier }
    }

    static func options(matching query: String, current: TimeZone) -> [Option] {
        let system = option(for: .autoupdatingCurrent)
        let systemName = String(localized: "System — \(system.name)")
        let systemShortcut = Option(
            zone: system.zone,
            name: systemName,
            searchIndex: "\(system.searchIndex) \(folded(systemName)) system"
        )
        var shortcuts = [systemShortcut, option(for: .gmt)]
        if !catalog.contains(where: { $0.id == current.identifier }) {
            shortcuts.append(makeOption(for: current))
        }
        var seen: Set<String> = []
        let terms = folded(query).split(whereSeparator: \.isWhitespace)
        return (shortcuts + catalog).filter { option in
            seen.insert(option.id).inserted && terms.allSatisfy { option.searchIndex.contains($0) }
        }
    }

    private static func option(for zone: TimeZone) -> Option {
        if let known = catalog.first(where: { $0.id == zone.identifier }) { return known }
        return makeOption(for: zone)
    }

    private static func makeOption(for zone: TimeZone) -> Option {
        let locale = Locale.autoupdatingCurrent
        let generic = zone.localizedName(for: .generic, locale: locale) ?? zone.identifier
        let name: String
        if zone.identifier == TimeZone.gmt.identifier {
            name = "UTC"
        } else if zone.identifier.contains("/"), !zone.identifier.hasPrefix("Etc/") {
            cityFormatter.timeZone = zone
            name = cityFormatter.string(from: Date(timeIntervalSince1970: 0))
        } else {
            name = generic
        }
        return Option(zone: zone, name: name, searchIndex: folded("\(name) \(generic) \(zone.identifier)"))
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .autoupdatingCurrent)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
    }

    private static let cityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "VVV" // The localized exemplar city.
        return formatter
    }()

    private static let catalog = TimeZone.knownTimeZoneIdentifiers
        .compactMap(TimeZone.init(identifier:))
        .map { makeOption(for: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
