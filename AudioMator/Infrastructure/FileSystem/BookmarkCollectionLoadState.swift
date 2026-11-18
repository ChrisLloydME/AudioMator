import Foundation

/// Loading state of a persisted bookmark collection.
///
/// The distinction between the cases drives save guards: a `.corrupt`
/// collection must never be overwritten, while `.notLoaded` triggers the
/// pre-save decode that protects a collection the store has not read yet.
/// No caller reads a record count from the state, so `.loaded` carries none.
enum BookmarkCollectionLoadState: Equatable {
    case notLoaded
    case empty
    case loaded
    case corrupt
}
