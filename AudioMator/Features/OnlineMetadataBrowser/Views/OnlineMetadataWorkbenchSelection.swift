enum OnlineMetadataWorkbenchPopUpMapping {
    static func selectionValues<Value>(for optionValues: [Value]) -> [Value?] {
        // NSPopUpButton item 0 is "Unassigned" and item 1 is a separator.
        [nil, nil] + optionValues.map(Optional.some)
    }
}
