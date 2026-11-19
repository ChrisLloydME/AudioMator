import Foundation
import TagLibAudioMetadata

/// One typed number-component operation the deterministic encoder will submit.
///
/// `value == nil` is an explicit removal, matching the semantic patch encoder.
/// Only the four structured number components may appear here.
nonisolated struct MetadataNumberComponentOperation: Sendable, Equatable {
    let field: MetadataFieldKey
    let value: Int?

    nonisolated init(field: MetadataFieldKey, value: Int?) {
        precondition(
            [.track, .trackTotal, .disc, .discTotal].contains(field),
            "Number component operations are limited to track/disc components."
        )
        self.field = field
        self.value = value
    }
}

/// Adapter-owned projection summary of a frozen write intent.
///
/// Planners use this as preview truth from the same deterministic encoder that
/// the eventual commit uses. The summary never authorizes a write by itself; the
/// executor still validates the reviewed target and the package validates the
/// captured revision.
///
/// - `requestedFields`: every semantic field the intent asks the writer to touch
///   (payload `requestedFields`, including companions).
/// - `effectiveFields`: the exact field operations the deterministic encoder
///   produced, including advisory and artwork when they changed.
/// - `componentOperations`: number-component intents with their target value.
/// - `unsupportedFields`: requested fields that concrete-format capability
///   information does not support. Missing capability information marks every
///   requested field unsupported (fail closed).
/// - `validation`: executable, rejected for an invalid payload, or unsupported
///   for a requested field the format cannot write.
nonisolated struct MetadataWriteProjection: Sendable, Equatable {
    enum Validation: Sendable, Equatable {
        case executable
        case rejected(String)
        case unsupported(Set<MetadataFieldKey>)
    }

    let requestedFields: Set<MetadataFieldKey>
    let effectiveFields: Set<MetadataFieldKey>
    let componentOperations: [MetadataNumberComponentOperation]
    let unsupportedFields: Set<MetadataFieldKey>
    let validation: Validation
    /// Encoder-derived "no operation" flag. Semantic writes derive it from the
    /// effective field/component set; raw writes derive it from an empty patch.
    /// Keeping it explicit prevents an empty `effectiveFields` from being read as
    /// a no-op for a nonempty raw patch, whose keys are not semantic fields.
    let isEncoderNoOp: Bool

    nonisolated init(
        requestedFields: Set<MetadataFieldKey> = [],
        effectiveFields: Set<MetadataFieldKey> = [],
        componentOperations: [MetadataNumberComponentOperation] = [],
        unsupportedFields: Set<MetadataFieldKey> = [],
        validation: Validation = .executable,
        isEncoderNoOp: Bool = false
    ) {
        self.requestedFields = requestedFields
        self.effectiveFields = effectiveFields
        self.componentOperations = componentOperations
        self.unsupportedFields = unsupportedFields
        self.validation = validation
        self.isEncoderNoOp = isEncoderNoOp
    }

    /// A projection that requests no change; callers treat this as a no-op.
    nonisolated static let noOp = MetadataWriteProjection(isEncoderNoOp: true)

    nonisolated var isExecutable: Bool {
        validation == .executable
    }

    nonisolated var isRejected: Bool {
        validation != .executable
    }

    /// Encoder-derived no-op: an executable intent with no field operations.
    nonisolated var isNoOp: Bool {
        isExecutable && isEncoderNoOp
    }

    nonisolated var rejectionMessage: String? {
        guard case .rejected(let message) = validation else { return nil }
        return message
    }
}
