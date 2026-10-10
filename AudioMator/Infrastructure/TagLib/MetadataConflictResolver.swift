import Foundation
import TagLibAudioMetadata

struct MetadataConflictError: LocalizedError {
    let fields: [String]

    nonisolated var errorDescription: String? {
        String(localized: "The same metadata fields changed on disk and in your draft. Your draft was kept; choose a conflict strategy in Settings or reload before editing.")
            + " " + fields.sorted().joined(separator: ", ")
    }
}

/// Runs inside the file mutation reservation. Every rebased write uses the
/// version of a newly verified read, including the dependency's final guard.
enum MetadataConflictResolver {
    nonisolated static func currentSnapshot(
        pipeline: any AudioMetadataPipeline,
        url: URL,
        originalFingerprint: AudioFileFingerprint
    ) throws -> MetadataSnapshot {
        let before = try AudioFileFingerprint.capture(at: url)
        // A replacement may be a different recording. A metadata projection
        // cannot establish audio identity, so even priority policies stop here.
        guard before.normalizedPath == originalFingerprint.normalizedPath,
              let device = originalFingerprint.fileSystemNumber,
              let inode = originalFingerprint.fileNumber,
              before.fileSystemNumber == device, before.fileNumber == inode else {
            throw AudioFileFingerprintValidationError.changedSincePreview(fileName: url.lastPathComponent)
        }
        let snapshot = try pipeline.conflictSnapshot(for: url)
        guard let version = snapshot.fileVersion,
              before == (try AudioFileFingerprint.capture(at: url)),
              version == (try pipeline.metadataFileVersion(at: url)) else {
            throw TagLibManagerError.fileChanged
        }
        return snapshot
    }

    nonisolated static func writeMetadata(
        _ edit: MetadataEditPayload,
        original: MetadataConflictBaseline,
        originalFingerprint: AudioFileFingerprint,
        originalVersion: MetadataFileVersion,
        policy: MetadataConflictPolicy,
        pipeline: any AudioMetadataPipeline,
        url: URL
    ) throws -> AudioMetadataWriteResult {
        let snapshot = try currentSnapshot(pipeline: pipeline, url: url, originalFingerprint: originalFingerprint)
        if snapshot.fileVersion == originalVersion {
            if TagLibAudioMetadataPipeline.metadataPatchForWrite(from: edit).isEmpty {
                return try noWriteResult(pipeline: pipeline, url: url, version: originalVersion)
            }
            return try pipeline.writeMetadata(edit, to: url, expectedVersion: originalVersion)
        }
        guard policy != .requireReload else { throw TagLibManagerError.fileChanged }
        let current = MetadataConflictBaseline(snapshot)
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: edit)
        var fields = Set(patch.fields.keys)
        if edit.contentAdvisoryChanged { fields.insert(.explicitContent) }
        if edit.trackNumberTextChanged { fields.formUnion([.track, .trackTotal]) }
        if edit.discNumberTextChanged { fields.formUnion([.disc, .discTotal]) }
        if case .unchanged = edit.artwork {} else { fields.insert(.artwork) }

        var resolved = edit
        var conflicts: [String] = []
        var discarded: [String] = []
        var visited = Set<MetadataFieldKey>()
        for field in fields {
            let group = fieldGroup(field)
            guard visited.isDisjoint(with: group) else { continue }
            visited.formUnion(group)
            guard !sameState(original, current, fields: group) else { continue }
            // Only accept exact single-field raw values as convergence. The
            // basic projection alone can conceal multi-values and aliases.
            let converged = group.count == 1 && patch.fields[field].map {
                matches($0, field: field, current: current)
            } == true
            if converged || policy == .preferDiskChanges {
                resolved.changedFields.subtract(group)
                if group.contains(.explicitContent) { resolved.contentAdvisoryChanged = false }
                if group.contains(.track) { resolved.trackNumberTextChanged = false }
                if group.contains(.disc) { resolved.discNumberTextChanged = false }
                if group.contains(.artwork) { resolved.artwork = .unchanged }
                if !converged { discarded.append(label(field)) }
            } else if policy == .mergeNonConflicting {
                conflicts.append(label(field))
            }
        }
        guard conflicts.isEmpty else { throw MetadataConflictError(fields: conflicts) }
        let resolvedPatch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: resolved)
        let result: AudioMetadataWriteResult
        if resolvedPatch.fields.isEmpty, resolvedPatch.explicitAdvisory == nil,
           resolvedPatch.numberText == nil, resolvedPatch.artwork == .unchanged {
            result = try noWriteResult(pipeline: pipeline, url: url, version: snapshot.fileVersion)
        } else {
            result = try pipeline.writeMetadata(resolved, to: url, expectedVersion: snapshot.fileVersion)
        }
        return addingDiscardWarning(discarded, to: result)
    }

    nonisolated static func writeRawMetadata(
        _ draft: RawMetadataValueMap,
        original: MetadataConflictBaseline,
        originalFingerprint: AudioFileFingerprint,
        originalVersion: MetadataFileVersion,
        policy: MetadataConflictPolicy,
        pipeline: any AudioMetadataPipeline,
        url: URL
    ) throws -> AudioMetadataWriteResult {
        let snapshot = try currentSnapshot(pipeline: pipeline, url: url, originalFingerprint: originalFingerprint)
        let current = MetadataConflictBaseline(snapshot)
        let revisionChanged = snapshot.fileVersion != originalVersion
        if revisionChanged && policy == .requireReload { throw TagLibManagerError.fileChanged }
        let editedKeys = Set(original.values.keys).union(draft.keys).filter { original.values[$0] != draft[$0] }
        var merged = current.values
        var visited = Set<String>()
        var conflicts: [String] = []
        var discarded: [String] = []
        for key in editedKeys.sorted() {
            let schemaField = MetadataFieldRegistry.schema(forPropertyMapKey: key)?.key
            let field = schemaField == .custom ? nil : schemaField
            let fields = field.map(fieldGroup) ?? []
            let keys = field.map { _ in propertyKeys(fields) } ?? [key]
            guard visited.isDisjoint(with: keys) else { continue }
            visited.formUnion(keys)
            let currentValues = current.values.filter { keys.contains($0.key) }
            let draftValues = draft.filter { keys.contains($0.key) }
            let changed = fields.isEmpty
                ? !sameCustomState(original, current, key: key)
                : !sameState(original, current, fields: fields)
            if revisionChanged && changed && currentValues != draftValues {
                if policy == .mergeNonConflicting {
                    conflicts.append(field.map(label) ?? key)
                    continue
                }
                if policy == .preferDiskChanges {
                    discarded.append(field.map(label) ?? key)
                    continue
                }
            }
            // Replace only the edited semantic group. Other keys, including
            // externally added custom keys and their value arrays, stay intact.
            for groupKey in keys { merged.removeValue(forKey: groupKey) }
            merged.merge(draftValues) { _, draft in draft }
        }
        guard conflicts.isEmpty else { throw MetadataConflictError(fields: conflicts) }
        let delta = RawMetadataPatch(
            valuesToSet: merged.filter { current.values[$0.key] != $0.value },
            removingKeys: Set(current.values.keys).subtracting(merged.keys)
        )
        let result = delta.valuesToSet.isEmpty && delta.removingKeys.isEmpty
            ? try noWriteResult(pipeline: pipeline, url: url, version: snapshot.fileVersion)
            : try pipeline.writeRawMetadataPatch(delta, to: url, expectedVersion: snapshot.fileVersion)
        return addingDiscardWarning(discarded, to: result)
    }

    nonisolated private static func noWriteResult(
        pipeline: any AudioMetadataPipeline, url: URL, version: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        guard let version, version == (try pipeline.metadataFileVersion(at: url)) else {
            throw TagLibManagerError.fileChanged
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated private static func addingDiscardWarning(
        _ fields: [String], to result: AudioMetadataWriteResult
    ) -> AudioMetadataWriteResult {
        guard !fields.isEmpty else { return result }
        return AudioMetadataWriteResult(
            warnings: result.warnings + [String(localized: "Kept disk changes instead of conflicting draft edits:") + " " + fields.sorted().joined(separator: ", ")],
            commitStatus: result.commitStatus
        )
    }

    nonisolated private static func label(_ field: MetadataFieldKey) -> String {
        MetadataFieldRegistry.schema(for: field)?.displayName ?? field.rawValue
    }

    nonisolated static func fieldGroup(_ field: MetadataFieldKey) -> Set<MetadataFieldKey> {
        switch field {
        case .track, .trackTotal: [.track, .trackTotal]
        case .disc, .discTotal: [.disc, .discTotal]
        // Some containers store the year and full date in the same item.
        case .date, .releaseDate: [.date, .releaseDate]
        case .performer, .musicianCredits: [.performer, .musicianCredits]
        default: [field]
        }
    }

    nonisolated private static func propertyKeys(_ fields: Set<MetadataFieldKey>) -> Set<String> {
        Set(fields.flatMap { MetadataFieldRegistry.schema(for: $0)?.propertyMapKeys ?? [] }.map { $0.uppercased() })
    }

    nonisolated private static func matches(
        _ value: MetadataPatchValue, field: MetadataFieldKey, current: MetadataConflictBaseline
    ) -> Bool {
        let values: [String]
        switch value {
        case .text(let text): values = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        case .values(let text): values = text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        case .integer(let number): values = [String(number)]
        case .boolean(let flag): values = [flag ? "1" : "0"]
        case .remove: values = []
        }
        let keys = propertyKeys([field])
        let present = current.values.filter { keys.contains($0.key) }
        return values.isEmpty ? present.isEmpty : present.count == 1 && present.values.first == values
    }

    nonisolated private static func sameState(
        _ original: MetadataConflictBaseline, _ current: MetadataConflictBaseline,
        fields: Set<MetadataFieldKey>
    ) -> Bool {
        let keys = propertyKeys(fields)
        guard original.values.filter({ keys.contains($0.key) }) == current.values.filter({ keys.contains($0.key) }) else { return false }
        let mappings = fields.flatMap { MetadataFieldRegistry.schema(for: $0)?.mappings ?? [] }
        let frameIDs = Set(mappings.filter { $0.format == .id3v2 && $0.storageKind != .userTextFrame }.flatMap(\.keys))
        let userDescriptions = Set(mappings.filter { $0.format == .id3v2 && $0.storageKind == .userTextFrame }.flatMap(\.keys).map { $0.uppercased() })
        let atoms = Set(mappings.filter { $0.format == .mp4 }.flatMap(\.keys))
        let freeforms = Set(mappings.filter { $0.format == .mp4 && $0.storageKind == .mp4Freeform }.flatMap(\.keys).map { $0.replacingOccurrences(of: "----:com.apple.iTunes:", with: "").uppercased() })
        func relevantFrame(_ frame: StructuredID3v2Frame) -> Bool {
            frameIDs.contains(frame.frameID) || (frame.frameID == "TXXX" && userDescriptions.contains((frame.description ?? "").uppercased()))
        }
        func relevantAtom(_ atom: StructuredMP4Atom) -> Bool {
            atoms.contains(atom.key) || freeforms.contains((atom.freeformDescription ?? "").uppercased())
        }
        let old = original.structured
        let new = current.structured
        guard old.id3v2Frames.filter(relevantFrame) == new.id3v2Frames.filter(relevantFrame),
              old.mp4Atoms.filter(relevantAtom) == new.mp4Atoms.filter(relevantAtom),
              old.asfAttributes == new.asfAttributes else { return false }
        // ASF registry mappings do not enumerate every native alias. Comparing
        // all attributes is conservative and avoids guessing affected roles.
        if fields.contains(.artwork) && old.artwork != new.artwork { return false }
        if fields.contains(.comment) && old.comments != new.comments { return false }
        if fields.contains(.lyrics) && old.lyrics != new.lyrics { return false }
        return true
    }

    nonisolated private static func sameCustomState(
        _ original: MetadataConflictBaseline, _ current: MetadataConflictBaseline, key: String
    ) -> Bool {
        guard original.values[key] == current.values[key] else { return false }
        // Unknown property keys have no reliable native storage mapping.
        // Be conservative if any native structures changed alongside them.
        return original.structured.id3v2Frames == current.structured.id3v2Frames
            && original.structured.mp4Atoms == current.structured.mp4Atoms
            && original.structured.asfAttributes == current.structured.asfAttributes
    }
}
