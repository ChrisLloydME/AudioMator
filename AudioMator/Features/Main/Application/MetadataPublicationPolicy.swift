import Foundation

/// How a completed reviewed write publishes its returned observation.
///
/// `immediate` publishes the accepted observation as soon as the mutation
/// returns. `batched` uses the existing deferred/throttled publication path so a
/// batch can publish once. Draft ownership decisions stay with the feature
/// session that owns them; this value only selects the publication cadence.
nonisolated enum MetadataPublicationPolicy: Sendable {
    case immediate
    case batched
}
