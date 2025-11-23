
import Foundation

enum Constants {
    enum Directory {
        fileprivate static func root(file: String = #file) -> URL {
            guard let path = file.components(separatedBy: "Tests").first else {
                fatalError("specify correct common parent directory for this file")
            }
            return URL(fileURLWithPath: path)
        }

        static func test() -> URL {
            let url = root()
                .appending(path: ".test")
                .appending(path: UUID().uuidString)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        static var audio: URL { root().appending(path: "Audio") }
    }
}
