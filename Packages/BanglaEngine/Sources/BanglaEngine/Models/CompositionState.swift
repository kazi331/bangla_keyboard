import Foundation

public struct CompositionState: Sendable, Hashable {
    public enum Phase: String, Sendable, Hashable {
        case idle
        case composing
        case showingCandidates
    }

    public var phase: Phase
    public var buffer: CompositionBuffer

    public init(phase: Phase = .idle, buffer: CompositionBuffer = CompositionBuffer()) {
        self.phase = phase
        self.buffer = buffer
    }

    public static let initial = CompositionState()
}

/// One piece of an in-progress transliteration.
public struct Segment: Sendable, Hashable {
    public var latin: String
    public var bangla: String
    public var alternates: [String]
    public var isCommitted: Bool

    public init(latin: String = "", bangla: String = "", alternates: [String] = [], isCommitted: Bool = false) {
        self.latin = latin
        self.bangla = bangla
        self.alternates = alternates
        self.isCommitted = isCommitted
    }

    public var range: Range<Int> {
        // computed when needed by the buffer
        0..<bangla.count
    }
}