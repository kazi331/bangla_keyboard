import Foundation
import BanglaEngine

/// Per-text-field composition state. Owned by the controller.
///
/// Not `@MainActor`: IMK invokes the controller's overrides on the main thread
/// by contract, so the session is single-threaded in practice without needing
/// compile-time actor isolation (which would conflict with IMK's non-isolated
/// Objective-C base-class methods).
public final class CompositionSession {
    public let id: UUID
    public var state: CompositionState
    public var candidateList: CandidateList
    public var selectedCandidateIndex: Int
    public var lastLayoutId: String

    public init(id: UUID = UUID(), layoutId: String) {
        self.id = id
        self.state = .initial
        self.candidateList = .empty
        self.selectedCandidateIndex = 0
        self.lastLayoutId = layoutId
    }

    public var buffer: CompositionBuffer { state.buffer }
    public var hasComposition: Bool { !state.buffer.isEmpty || state.phase != .idle }

    public func reset() {
        state = .initial
        candidateList = .empty
        selectedCandidateIndex = 0
    }

    public func selectCandidate(at index: Int) -> Candidate? {
        guard candidateList.entries.indices.contains(index) else { return nil }
        return candidateList.entries[index]
    }

    public func moveSelection(by delta: Int) -> Int {
        guard !candidateList.entries.isEmpty else { return 0 }
        let n = candidateList.entries.count
        selectedCandidateIndex = (selectedCandidateIndex + delta) % n
        if selectedCandidateIndex < 0 { selectedCandidateIndex += n }
        return selectedCandidateIndex
    }
}