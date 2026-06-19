import Foundation

/// A ranked candidate Bangla string proposed to the user.
public struct Candidate: Hashable, Sendable, Identifiable {
    public let id: String        // bangla text acts as identity
    public let bangla: String
    public let latinHint: String
    public var source: CandidateSource
    public var score: Double
    public var useCount: Int
    public var lastUsedAt: Date

    public init(
        bangla: String,
        latinHint: String = "",
        source: CandidateSource = .lexicon,
        score: Double = 0,
        useCount: Int = 0,
        lastUsedAt: Date = .distantPast
    ) {
        self.id = bangla
        self.bangla = bangla
        self.latinHint = latinHint
        self.source = source
        self.score = score
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    public enum CandidateSource: String, Sendable, Hashable {
        case lexicon
        case user
        case lm
        case editdist
    }
}

public struct CandidateList: Sendable {
    public let primary: Candidate?
    public let entries: [Candidate]
    public let latencyMs: Double

    public init(primary: Candidate?, entries: [Candidate], latencyMs: Double = 0) {
        self.primary = primary
        self.entries = entries
        self.latencyMs = latencyMs
    }

    public static let empty = CandidateList(primary: nil, entries: [])
}