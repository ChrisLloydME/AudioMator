import Foundation

enum FuzzyStringSimilarity {
    nonisolated static func score(_ lhs: String, _ rhs: String) -> Double {
        let normalizedLHS = normalize(lhs)
        let normalizedRHS = normalize(rhs)
        guard !normalizedLHS.isEmpty, !normalizedRHS.isEmpty else { return 0 }

        if normalizedLHS == normalizedRHS {
            return 1
        }

        if normalizedLHS.contains(normalizedRHS) || normalizedRHS.contains(normalizedLHS) {
            return 0.92
        }

        let tokenScore = jaccardSimilarity(
            Set(tokens(in: normalizedLHS)),
            Set(tokens(in: normalizedRHS))
        )
        let editScore = normalizedEditSimilarity(normalizedLHS, normalizedRHS)
        let prefixScore = commonPrefixSimilarity(normalizedLHS, normalizedRHS)

        return min(1, (editScore * 0.6) + (tokenScore * 0.3) + (prefixScore * 0.1))
    }

    nonisolated static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: .current
        )
        let mappedScalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mappedScalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    nonisolated static func tokens(in normalizedValue: String) -> [String] {
        normalizedValue
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    nonisolated static func tokenSequenceContains(_ value: String, sequence: String) -> Bool {
        let valueTokens = tokens(in: value)
        let sequenceTokens = tokens(in: sequence)
        guard !valueTokens.isEmpty, !sequenceTokens.isEmpty else { return false }
        guard sequenceTokens.count <= valueTokens.count else { return false }

        for startIndex in 0...(valueTokens.count - sequenceTokens.count) {
            let candidate = valueTokens[startIndex..<(startIndex + sequenceTokens.count)]
            if Array(candidate) == sequenceTokens {
                return true
            }
        }

        return false
    }

    private nonisolated static func jaccardSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let unionCount = lhs.union(rhs).count
        guard unionCount > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(unionCount)
    }

    private nonisolated static func commonPrefixSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let maxLength = max(lhsCharacters.count, rhsCharacters.count)
        guard maxLength > 0 else { return 0 }

        var prefixLength = 0
        for (lhsCharacter, rhsCharacter) in zip(lhsCharacters, rhsCharacters) {
            guard lhsCharacter == rhsCharacter else { break }
            prefixLength += 1
        }

        return Double(prefixLength) / Double(maxLength)
    }

    private nonisolated static func normalizedEditSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let maxLength = max(lhsCharacters.count, rhsCharacters.count)
        guard maxLength > 0 else { return 0 }

        let distance = levenshteinDistance(lhsCharacters, rhsCharacters)
        return max(0, 1 - (Double(distance) / Double(maxLength)))
    }

    private nonisolated static func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previousRow = Array(0...rhs.count)
        var currentRow = Array(repeating: 0, count: rhs.count + 1)

        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            currentRow[0] = lhsIndex + 1

            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let substitutionCost = lhsCharacter == rhsCharacter ? 0 : 1
                currentRow[rhsIndex + 1] = min(
                    previousRow[rhsIndex + 1] + 1,
                    currentRow[rhsIndex] + 1,
                    previousRow[rhsIndex] + substitutionCost
                )
            }

            swap(&previousRow, &currentRow)
        }

        return previousRow[rhs.count]
    }
}
