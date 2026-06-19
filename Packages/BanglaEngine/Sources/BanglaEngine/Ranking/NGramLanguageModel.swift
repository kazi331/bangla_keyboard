import Foundation

/// 3-gram language model with online counts. Reads/writes through
/// UserRepository; in-memory cache for hot path.
public actor NGramLanguageModel {
    private var counts: [String: [String: Int]] = [:]   // context -> token -> count
    private var contextTotals: [String: Int] = [:]
    private let totalVocab: Int

    public init(totalVocab: Int = 50_000) {
        self.totalVocab = max(1, totalVocab)
    }

    public func observe(context: [String], token: String) {
        let key = context.suffix(2).joined(separator: " ")
        counts[key, default: [:]][token, default: 0] += 1
        contextTotals[key, default: 0] += 1
    }

    /// P(token | context) with add-one smoothing over a fixed vocab.
    public func probability(context: [String], token: String) -> Double {
        let key = context.suffix(2).joined(separator: " ")
        let c = counts[key]?[token] ?? 0
        let total = contextTotals[key] ?? 0
        return Double(c + 1) / Double(total + totalVocab)
    }

    public func suggest(context: [String], prefix: String, limit: Int) -> [String] {
        let key = context.suffix(2).joined(separator: " ")
        guard let dist = counts[key] else { return [] }
        return dist
            .filter { prefix.isEmpty || $0.key.hasPrefix(prefix) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
}