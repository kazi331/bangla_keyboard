import Foundation

/// Damerau-Levenshtein edit distance with transposition support.
/// Used as a typo fallback when the lexicon returns too few candidates.
public enum EditDistance {
    public static func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count
        if aLen == 0 { return bLen }
        if bLen == 0 { return aLen }

        var d = Array(repeating: Array(repeating: 0, count: bLen + 1), count: aLen + 1)
        for i in 0...aLen { d[i][0] = i }
        for j in 0...bLen { d[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                d[i][j] = min(
                    d[i-1][j]   + 1,   // deletion
                    d[i][j-1]   + 1,   // insertion
                    d[i-1][j-1] + cost // substitution
                )
                if i > 1 && j > 1,
                   aChars[i-1] == bChars[j-2],
                   aChars[i-2] == bChars[j-1] {
                    d[i][j] = min(d[i][j], d[i-2][j-2] + 1) // transposition
                }
            }
        }
        return d[aLen][bLen]
    }
}

public struct EditDistanceScorer: Sendable {
    public let maxThreshold: Int

    public init(maxThreshold: Int = 2) {
        self.maxThreshold = maxThreshold
    }

    /// Returns a score in [0,1] where 1 = exact match.
    public func score(_ query: String, against target: String) -> Double {
        let dist = EditDistance.damerauLevenshtein(query, target)
        if dist > maxThreshold { return 0 }
        let maxLen = max(query.count, target.count)
        if maxLen == 0 { return 1 }
        return Double(maxLen - dist) / Double(maxLen)
    }
}