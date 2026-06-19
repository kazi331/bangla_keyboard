import Foundation

/// Combines per-source scores with recency/frequency/context boosts and
/// length penalty. Pure function of inputs.
public struct PersonalizationBlend: Sendable {
    public struct Coefficients: Sendable {
        public let wLex: Double
        public let wUser: Double
        public let wLM: Double
        public let wED: Double
        public let lambdaRecency: Double
        public let lambdaFrequency: Double
        public let lambdaContext: Double
        public let lambdaApp: Double
        public let lambdaLength: Double
        public let tauRecencyDays: Double

        public static let `default` = Coefficients(
            wLex: 1.0, wUser: 1.6, wLM: 1.3, wED: 0.3,
            lambdaRecency: 0.15, lambdaFrequency: 0.10,
            lambdaContext: 0.25, lambdaApp: 0.05, lambdaLength: 0.02,
            tauRecencyDays: 14.0
        )
    }

    public let coeffs: Coefficients
    public let editDistanceScorer: EditDistanceScorer

    public init(coeffs: Coefficients = .default, editDistanceScorer: EditDistanceScorer = .init()) {
        self.coeffs = coeffs
        self.editDistanceScorer = editDistanceScorer
    }

    public func blend(
        candidate: Candidate,
        latinQuery: String,
        banglaPrefix: String,
        context: [String],
        appPrior: Double,
        now: Date = Date()
    ) -> Double {
        let sourceWeight: Double
        switch candidate.source {
        case .lexicon:  sourceWeight = coeffs.wLex
        case .user:     sourceWeight = coeffs.wUser
        case .lm:       sourceWeight = coeffs.wLM
        case .editdist: sourceWeight = coeffs.wED
        }
        let base = sourceWeight * candidate.score

        let daysSince = max(0, now.timeIntervalSince(candidate.lastUsedAt) / 86_400.0)
        let recency = coeffs.lambdaRecency * exp(-daysSince / coeffs.tauRecencyDays)

        let frequency = coeffs.lambdaFrequency * log(1.0 + Double(candidate.useCount))

        // Context boost is computed upstream (NGramLanguageModel) and folded
        // into candidate.score by the pipeline before calling blend for LM
        // candidates; we expose a hook here for future use.
        let context = coeffs.lambdaContext * 0   // (folded upstream)

        let app = coeffs.lambdaApp * appPrior

        let length = -coeffs.lambdaLength * Double(candidate.bangla.count)

        // Edit-distance candidates get an extra refinement against the latin query.
        let ed: Double
        if candidate.source == .editdist {
            ed = editDistanceScorer.score(latinQuery, against: candidate.latinHint) * 0.3
        } else {
            ed = 0
        }

        return base + recency + frequency + context + app + length + ed
    }
}