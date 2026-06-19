import Foundation

/// Scores raw lexicon candidates by base frequency and latin-prefix match.
public struct LexiconScorer: Sendable {
    public let exactMatchBoost: Double
    public let prefixMatchBoost: Double

    public init(exactMatchBoost: Double = 0.5, prefixMatchBoost: Double = 0.2) {
        self.exactMatchBoost = exactMatchBoost
        self.prefixMatchBoost = prefixMatchBoost
    }

    public func score(
        candidate: Candidate,
        latinQuery: String,
        banglaPrefix: String
    ) -> Double {
        var s = candidate.score  // base_freq from lexicon
        if !candidate.latinHint.isEmpty,
           candidate.latinHint.lowercased() == latinQuery.lowercased() {
            s += exactMatchBoost
        } else if !latinQuery.isEmpty,
                  candidate.latinHint.lowercased().hasPrefix(latinQuery.lowercased()) {
            s += prefixMatchBoost
        }
        if !banglaPrefix.isEmpty,
           candidate.bangla.hasPrefix(banglaPrefix) {
            s += 0.1
        }
        return s
    }
}