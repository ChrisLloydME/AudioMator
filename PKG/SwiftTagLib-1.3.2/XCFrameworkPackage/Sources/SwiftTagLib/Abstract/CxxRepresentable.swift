
/// A type that can be initialized with an equivalent `C++` type and can also create its `C++` representation from `self`.
protocol CxxRepresentable {
    associatedtype CxxRepresentation
    init(cxxRepresentation: CxxRepresentation)
    var cxxRepresentation: CxxRepresentation { get }
}
