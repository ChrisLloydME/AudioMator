
import Foundation
import ArgumentParser
import SwiftTagLib

@main
struct MetadataReader: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reads metadata from AudioFile using SwiftTagLib"
    )

    @Argument(help: "path to AudioFile") var path: URL

    func run() throws {
        let file = try AudioFile(url: path)
        print("File: \(path.lastPathComponent)")
        print("--------------------------------------------------")
        print("Metadata:")
        let padding = "  "
        Mirror(reflecting: file.metadata).children.forEach { label, value in
            guard
                let label,
                /// ignore the compiler warning below, this is needed to get rid of `Optional` in `print`
                let value = value as? Optional<Any>
            else { return }
            
            if let value {
                print("\(padding)\(label): \(value)")
            } else {
                print("\(padding)\(label): nil")
            }
        }
    }
}

extension URL: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(fileURLWithPath: argument)
    }
}
