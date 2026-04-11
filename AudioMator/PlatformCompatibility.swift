import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit

typealias NSImage = UIImage
typealias NSFont = UIFont
typealias NSColor = UIColor

extension UIImage {
    var tiffRepresentation: Data? { pngData() }
}

enum NSBitmapImageRepFileType {
    case png
}

final class NSBitmapImageRep {
    private let imageData: Data

    init?(data: Data) {
        guard !data.isEmpty else { return nil }
        self.imageData = data
    }

    func representation(using storageType: NSBitmapImageRepFileType, properties: [AnyHashable: Any]) -> Data? {
        _ = storageType
        imageData
    }
}
#endif
