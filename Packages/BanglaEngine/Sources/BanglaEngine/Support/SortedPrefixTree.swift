import Foundation

/// In-memory sorted prefix tree used as a fallback when FTS5 is
/// unavailable or for tests. Not the primary lookup path.
public final class SortedPrefixTree: @unchecked Sendable {
    private final class Node: @unchecked Sendable {
        var candidates: [Candidate] = []
        var children: [Character: Node] = [:]
    }
    private let root = Node()
    private let lock = NSLock()

    public init() {}

    public func insert(_ candidate: Candidate) {
        lock.lock(); defer { lock.unlock() }
        var node = root
        for ch in candidate.bangla {
            if let next = node.children[ch] {
                node = next
            } else {
                let next = Node()
                node.children[ch] = next
                node = next
            }
        }
        node.candidates.append(candidate)
    }

    public func search(prefix: String, limit: Int = 16) -> [Candidate] {
        lock.lock(); defer { lock.unlock() }
        var node = root
        for ch in prefix {
            guard let next = node.children[ch] else { return [] }
            node = next
        }
        var results: [Candidate] = []
        collect(from: node, into: &results, limit: limit)
        return results.sorted { $0.score > $1.score }
    }

    private func collect(from node: Node, into results: inout [Candidate], limit: Int) {
        if results.count >= limit { return }
        results.append(contentsOf: node.candidates)
        for child in node.children.values {
            if results.count >= limit { return }
            collect(from: child, into: &results, limit: limit)
        }
    }
}