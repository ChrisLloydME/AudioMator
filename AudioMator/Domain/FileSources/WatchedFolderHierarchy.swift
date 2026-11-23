import Foundation

nonisolated struct WatchedFolderNode: Identifiable, Hashable, Sendable {
    let rootFolderID: UUID
    /// Normalized path key relative to the watched folder root (e.g. `"album a/disc 1"`).
    let relativePathKey: String
    /// Original display path components relative to the watched folder root.
    let relativePathComponents: [String]
    /// Folder display name (the final path component).
    let displayName: String
    /// Standardized on-disk URL for this subfolder.
    let url: URL
    /// Immediate child subfolders in Finder-like natural order.
    let children: [WatchedFolderNode]

    var selection: SidebarSelection {
        .watchedSubfolder(rootFolderID: rootFolderID, relativePathKey: relativePathKey)
    }

    var id: SidebarSelection { selection }

    var relativeDisplayPath: String {
        relativePathComponents.joined(separator: " / ")
    }

    var hasChildren: Bool {
        !children.isEmpty
    }
}

/// On-disk subfolder hierarchy derived purely from filesystem paths under one
/// watched-folder root. Works even when every audio file is completely untagged.
nonisolated struct WatchedFolderHierarchy: Equatable, Sendable {
    let rootFolderID: UUID
    let rootURL: URL
    let rootCanonicalPath: String
    let rootKeyComponents: [String]
    let rootIsCaseSensitive: Bool
    let rootChildren: [WatchedFolderNode]
    let nodesByRelativePathKey: [String: WatchedFolderNode]
    private let relativePathKeyByDirectoryPath: [String: String]

    static func build(
        rootFolderID: UUID,
        rootURL: URL,
        directoryURLs: [URL],
        audioFileURLs: [URL] = []
    ) -> WatchedFolderHierarchy {
        let standardizedRootURL = rootURL.standardizedFileURL
        let rootResolution = FileSystemPathSemantics.identityResolution(for: standardizedRootURL)
        let rootComponents = pathComponents(of: rootResolution.canonicalPath)
        let rootKeyComponents = rootComponents.map {
            componentKey($0, isCaseSensitive: rootResolution.isCaseSensitive)
        }

        var relativePathKeyByDirectoryPath: [String: String] = [:]
        relativePathKeyByDirectoryPath[standardizedRootURL.path] = ""
        relativePathKeyByDirectoryPath[rootResolution.canonicalPath] = ""

        let rootBuilder = NodeBuilder(displayName: "", relativePathKey: "", relativePathComponents: [])
        var seenCandidateStandardizedPaths = Set<String>()

        let candidateDirectoryURLs = directoryURLs + audioFileURLs.map {
            $0.standardizedFileURL.deletingLastPathComponent()
        }

        for rawDirectoryURL in candidateDirectoryURLs {
            let standardizedURL = rawDirectoryURL.standardizedFileURL
            guard seenCandidateStandardizedPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            let canonicalURL = standardizedURL.resolvingSymlinksInPath()
            let candidateComponents = pathComponents(of: canonicalURL.path)
            guard let relativeComponents = relativeDisplayComponents(
                of: candidateComponents,
                underRootKeyComponents: rootKeyComponents,
                isCaseSensitive: rootResolution.isCaseSensitive
            ) else {
                continue
            }

            if relativeComponents.isEmpty {
                relativePathKeyByDirectoryPath[standardizedURL.path] = ""
                relativePathKeyByDirectoryPath[canonicalURL.path] = ""
                continue
            }

            let relativeKey = insertRelativePath(
                relativeComponents,
                into: rootBuilder,
                isCaseSensitive: rootResolution.isCaseSensitive
            )
            relativePathKeyByDirectoryPath[standardizedURL.path] = relativeKey
            relativePathKeyByDirectoryPath[canonicalURL.path] = relativeKey
        }

        var nodesByRelativePathKey: [String: WatchedFolderNode] = [:]
        let rootChildren = buildSortedChildren(
            from: rootBuilder,
            rootFolderID: rootFolderID,
            parentURL: standardizedRootURL,
            nodesByRelativePathKey: &nodesByRelativePathKey
        )

        return WatchedFolderHierarchy(
            rootFolderID: rootFolderID,
            rootURL: standardizedRootURL,
            rootCanonicalPath: rootResolution.canonicalPath,
            rootKeyComponents: rootKeyComponents,
            rootIsCaseSensitive: rootResolution.isCaseSensitive,
            rootChildren: rootChildren,
            nodesByRelativePathKey: nodesByRelativePathKey,
            relativePathKeyByDirectoryPath: relativePathKeyByDirectoryPath
        )
    }

    func node(forRelativePathKey key: String) -> WatchedFolderNode? {
        nodesByRelativePathKey[key]
    }

    func containsSubfolder(relativePathKey key: String) -> Bool {
        nodesByRelativePathKey[key] != nil
    }

    /// Returns `relativePathKey` if it still exists, otherwise walks upward
    /// through surviving ancestors and falls back to the watched folder root.
    func nearestSurvivingSelection(for relativePathKey: String) -> SidebarSelection {
        var candidate = relativePathKey
        while !candidate.isEmpty {
            if nodesByRelativePathKey[candidate] != nil {
                return .watchedSubfolder(rootFolderID: rootFolderID, relativePathKey: candidate)
            }
            if let slashIndex = candidate.lastIndex(of: "/") {
                candidate = String(candidate[..<slashIndex])
            } else {
                break
            }
        }
        return .watchedFolder(rootFolderID)
    }

    func relativePathKey(forDirectoryURL directoryURL: URL) -> String? {
        let standardizedURL = directoryURL.standardizedFileURL
        if let cached = relativePathKeyByDirectoryPath[standardizedURL.path] {
            return cached
        }

        let canonicalURL = standardizedURL.resolvingSymlinksInPath()
        if let cached = relativePathKeyByDirectoryPath[canonicalURL.path] {
            return cached
        }

        let components = Self.pathComponents(of: canonicalURL.path)
        guard let relativeComponents = Self.relativeDisplayComponents(
            of: components,
            underRootKeyComponents: rootKeyComponents,
            isCaseSensitive: rootIsCaseSensitive
        ) else {
            return nil
        }

        return relativeComponents
            .map { Self.componentKey($0, isCaseSensitive: rootIsCaseSensitive) }
            .joined(separator: "/")
    }

    func containsFile(at fileURL: URL, withinRelativePathKey selectedRelativePathKey: String) -> Bool {
        let parentURL = fileURL.standardizedFileURL.deletingLastPathComponent()
        guard let directoryRelativePathKey = relativePathKey(forDirectoryURL: parentURL) else {
            return false
        }
        return Self.isSameOrDescendant(directoryRelativePathKey, of: selectedRelativePathKey)
    }

    static func isSameOrDescendant(
        _ candidateRelativePathKey: String,
        of ancestorRelativePathKey: String
    ) -> Bool {
        if ancestorRelativePathKey.isEmpty {
            return true
        }
        if candidateRelativePathKey == ancestorRelativePathKey {
            return true
        }
        return candidateRelativePathKey.hasPrefix(ancestorRelativePathKey + "/")
    }

    // MARK: - Private tree builder

    private final class NodeBuilder {
        let displayName: String
        let relativePathKey: String
        let relativePathComponents: [String]
        var childrenByKey: [String: NodeBuilder] = [:]

        init(displayName: String, relativePathKey: String, relativePathComponents: [String]) {
            self.displayName = displayName
            self.relativePathKey = relativePathKey
            self.relativePathComponents = relativePathComponents
        }
    }

    private static func insertRelativePath(
        _ relativeComponents: [String],
        into root: NodeBuilder,
        isCaseSensitive: Bool
    ) -> String {
        var current = root
        var accumulatedKeyComponents: [String] = []
        var accumulatedDisplayComponents: [String] = []

        for rawComponent in relativeComponents {
            let displayComponent = rawComponent.precomposedStringWithCanonicalMapping
            let keyComponent = componentKey(displayComponent, isCaseSensitive: isCaseSensitive)
            accumulatedKeyComponents.append(keyComponent)
            accumulatedDisplayComponents.append(displayComponent)
            let cumulativeKey = accumulatedKeyComponents.joined(separator: "/")

            if let existing = current.childrenByKey[keyComponent] {
                current = existing
            } else {
                let next = NodeBuilder(
                    displayName: displayComponent,
                    relativePathKey: cumulativeKey,
                    relativePathComponents: accumulatedDisplayComponents
                )
                current.childrenByKey[keyComponent] = next
                current = next
            }
        }

        return current.relativePathKey
    }

    private static func buildSortedChildren(
        from builder: NodeBuilder,
        rootFolderID: UUID,
        parentURL: URL,
        nodesByRelativePathKey: inout [String: WatchedFolderNode]
    ) -> [WatchedFolderNode] {
        let sortedBuilders = builder.childrenByKey.values.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if lhs.relativePathKey != rhs.relativePathKey {
                return lhs.relativePathKey < rhs.relativePathKey
            }
            return lhs.displayName < rhs.displayName
        }

        return sortedBuilders.map { childBuilder in
            let childURL = parentURL.appendingPathComponent(childBuilder.displayName, isDirectory: true)
            let grandChildren = buildSortedChildren(
                from: childBuilder,
                rootFolderID: rootFolderID,
                parentURL: childURL,
                nodesByRelativePathKey: &nodesByRelativePathKey
            )
            let node = WatchedFolderNode(
                rootFolderID: rootFolderID,
                relativePathKey: childBuilder.relativePathKey,
                relativePathComponents: childBuilder.relativePathComponents,
                displayName: childBuilder.displayName,
                url: childURL,
                children: grandChildren
            )
            nodesByRelativePathKey[node.relativePathKey] = node
            return node
        }
    }

    private static func pathComponents(of canonicalPath: String) -> [String] {
        canonicalPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func componentKey(_ component: String, isCaseSensitive: Bool) -> String {
        FileSystemPathSemantics.comparisonKey(
            forCanonicalPath: component,
            isCaseSensitive: isCaseSensitive
        )
    }

    private static func relativeDisplayComponents(
        of candidateComponents: [String],
        underRootKeyComponents rootKeyComponents: [String],
        isCaseSensitive: Bool
    ) -> [String]? {
        guard candidateComponents.count >= rootKeyComponents.count else {
            return nil
        }

        for index in rootKeyComponents.indices {
            if componentKey(candidateComponents[index], isCaseSensitive: isCaseSensitive) != rootKeyComponents[index] {
                return nil
            }
        }

        return Array(candidateComponents.dropFirst(rootKeyComponents.count))
    }
}
