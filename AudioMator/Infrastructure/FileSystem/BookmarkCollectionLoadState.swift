import Foundation

enum BookmarkCollectionLoadState: Equatable {
    case notLoaded
    case empty
    case loaded(recordCount: Int)
    case corrupt
}
