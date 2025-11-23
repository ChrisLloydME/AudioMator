
@testable import SwiftTagLib

extension AudioFile.Metadata.AttachedPicture: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue < rhs.hashValue
    }
}
