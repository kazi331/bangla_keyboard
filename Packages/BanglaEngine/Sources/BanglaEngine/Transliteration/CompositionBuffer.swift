import Foundation

/// Holds the in-progress transliteration as a list of segments.
/// Supports per-segment re-edit (clicking a segment in the UI
/// re-opens alternates without re-typing) and dependency-aware
/// backspace for conjuncts.
public struct CompositionBuffer: Sendable, Hashable {
    public private(set) var segments: [Segment]
    public private(set) var cursorSegment: Int

    public init(segments: [Segment] = [], cursorSegment: Int = 0) {
        self.segments = segments
        self.cursorSegment = cursorSegment
    }

    public var isEmpty: Bool { segments.allSatisfy { $0.latin.isEmpty && $0.bangla.isEmpty } }

    /// Latin text typed so far (concatenation of all segments' latin).
    public var latin: String {
        segments.reduce(into: "") { $0 += $1.latin }
    }

    /// Currently displayed Bangla (concatenation of all segments).
    public var bangla: String {
        segments.reduce(into: "") { $0 += $1.bangla }
    }

    /// The currently active (mutable) segment, or nil if buffer is empty.
    public var current: Segment? {
        guard segments.indices.contains(cursorSegment) else { return nil }
        return segments[cursorSegment]
    }

    public mutating func append(latin: String, bangla: String, alternates: [String] = []) {
        if segments.indices.contains(cursorSegment) && !segments[cursorSegment].isCommitted {
            segments[cursorSegment].latin += latin
            segments[cursorSegment].bangla += bangla
            segments[cursorSegment].alternates = alternates
        } else {
            segments.append(Segment(latin: latin, bangla: bangla, alternates: alternates))
            cursorSegment = segments.count - 1
        }
    }

    /// Replace the current segment's Bangla output (e.g. when user
    /// picks an alternate candidate).
    public mutating func replaceCurrent(bangla: String, alternates: [String] = []) {
        guard segments.indices.contains(cursorSegment) else { return }
        segments[cursorSegment].bangla = bangla
        segments[cursorSegment].alternates = alternates
    }

    public mutating func commitCurrent() {
        guard segments.indices.contains(cursorSegment) else { return }
        segments[cursorSegment].isCommitted = true
        cursorSegment = segments.count  // new chars will start a fresh segment
    }

    /// Backspace: drop last char of current segment's latin; if empty,
    /// remove the segment and step back. Returns true if the buffer
    /// still has content.
    @discardableResult
    public mutating func backspace() -> Bool {
        guard !segments.isEmpty else { return false }
        if cursorSegment >= segments.count { cursorSegment = segments.count - 1 }
        guard segments.indices.contains(cursorSegment) else { return false }
        let seg = segments[cursorSegment]
        if !seg.latin.isEmpty {
            segments[cursorSegment].latin.removeLast()
            segments[cursorSegment].bangla.removeLast()
            if segments[cursorSegment].latin.isEmpty {
                segments.remove(at: cursorSegment)
                cursorSegment = max(0, cursorSegment - 1)
            }
        } else {
            segments.remove(at: cursorSegment)
            cursorSegment = max(0, cursorSegment - 1)
        }
        return !isEmpty
    }

    public mutating func clear() {
        segments.removeAll()
        cursorSegment = 0
    }
}