import Foundation

/// Orchestrates the four sources (lexicon, user, lm, edit-distance) and
/// produces a final ranked CandidateList. The pipeline does NOT own
/// database connections; it accepts pre-fetched candidate sets and a
/// language model handle.
public struct ScoringPipeline: Sendable {
    public let blend: PersonalizationBlend
    public let maxCandidates: Int
    public let lexiconScorer: LexiconScorer

    public init(
        blend: PersonalizationBlend = .init(),
        maxCandidates: Int = 9,
        lexiconScorer: LexiconScorer = .init()
    ) {
        self.blend = blend
        self.maxCandidates = maxCandidates
        self.lexiconScorer = lexiconScorer
    }

    public struct Inputs: Sendable {
        public let latinQuery: String
        public let banglaPrefix: String
        public let context: [String]          // prior committed tokens
        public let appPrior: Double
        public let lexicon: [Candidate]
        public let user: [Candidate]
        public let lm: [Candidate]
        public let editDistance: [Candidate]

        public init(
            latinQuery: String,
            banglaPrefix: String,
            context: [String] = [],
            appPrior: Double = 0,
            lexicon: [Candidate] = [],
            user: [Candidate] = [],
            lm: [Candidate] = [],
            editDistance: [Candidate] = []
        ) {
            self.latinQuery = latinQuery
            self.banglaPrefix = banglaPrefix
            self.context = context
            self.appPrior = appPrior
            self.lexicon = lexicon
            self.user = user
            self.lm = lm
            self.editDistance = editDistance
        }
    }

    public func rank(_ inputs: Inputs, now: Date = Date()) -> CandidateList {
        let start = Date()

        // Stage 1: source-specific base scoring.
        let lex = inputs.lexicon.map { c -> Candidate in
            var n = c
            n.score = lexiconScorer.score(candidate: c, latinQuery: inputs.latinQuery, banglaPrefix: inputs.banglaPrefix)
            return n
        }
        let usr = inputs.user.map { c -> Candidate in
            var n = c
            n.score = c.score + 0.1   // small base for user entries
            return n
        }
        let lm = inputs.lm
        let ed = inputs.editDistance.map { c -> Candidate in
            var n = c
            n.score = c.score
            return n
        }

        // Stage 2: blend.
        let all = (lex + usr + lm + ed).map { c -> Candidate in
            var n = c
            n.score = blend.blend(
                candidate: c,
                latinQuery: inputs.latinQuery,
                banglaPrefix: inputs.banglaPrefix,
                context: inputs.context,
                appPrior: inputs.appPrior,
                now: now
            )
            return n
        }

        // Stage 3: dedupe (keep max score per bangla string).
        var byKey: [String: Candidate] = [:]
        for c in all {
            if let existing = byKey[c.bangla] {
                if c.score > existing.score { byKey[c.bangla] = c }
            } else {
                byKey[c.bangla] = c
            }
        }

        // Stage 4: sort + tie-break.
        let sorted = byKey.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.latinHint == inputs.latinQuery && rhs.latinHint != inputs.latinQuery { return true }
            if rhs.latinHint == inputs.latinQuery && lhs.latinHint != inputs.latinQuery { return false }
            return lhs.bangla < rhs.bangla
        }

        let trimmed = Array(sorted.prefix(maxCandidates))
        let primary = trimmed.first
        let ms = -start.timeIntervalSinceNow * 1000
        return CandidateList(primary: primary, entries: trimmed, latencyMs: ms)
    }
}