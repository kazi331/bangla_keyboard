import Foundation

/// Longest-match phonetic resolver for Avro-compatible rules.
///
/// Consumes a stream of latin characters and produces:
///   - the maximal Bangla string per the rule set
///   - alternate parses for ambiguous inputs (e.g. "rri" -> ৃ | রি)
///
/// The resolver operates on the current latin buffer; it does not
/// maintain state between keystrokes. Callers should feed the full
/// latin composition buffer each time.
public struct PhoneticResolver: Sendable {
    public let layout: Layout

    /// Trie of rules indexed by latin match.
    private let trie: RuleTrie

    public init(layout: Layout) {
        self.layout = layout
        let trie = RuleTrie()
        for r in layout.rules { trie.insert(r) }
        // Vowel signs and consonant endings behave as rules too.
        for (k, v) in layout.vowelSigns {
            trie.insert(PhoneticRule(match: k, output: v, weight: 1.0))
        }
        for (k, v) in layout.independentVowels {
            // Slightly lower weight so a consonant-ending rule (e.g. "a"->া) is
            // preferred after consonants; independent vowel wins at word start via
            // the context check in resolve().
            trie.insert(PhoneticRule(match: k, output: v, weight: 0.8))
        }
        for (k, v) in layout.consonantEndings {
            trie.insert(PhoneticRule(match: k, output: v, weight: 0.9))
        }
        for (k, v) in layout.specials {
            trie.insert(PhoneticRule(match: k, output: v, weight: 1.0))
        }
        self.trie = trie
    }

    public struct Resolution: Sendable, Equatable {
        public let bangla: String
        public let alternates: [String]
        /// latin substring that was consumed to produce `bangla`.
        public let consumedLatin: String
        /// latin substring that remains unconsumed (no rule matched).
        public let remainder: String
    }

    /// Resolve the entire latin buffer to a Bangla string + alternates.
    public func resolve(_ latin: String) -> Resolution {
        var output = ""
        var alternates: [String] = []
        var i = latin.startIndex
        var lastConsumedEnd = latin.startIndex
        var lastEmittedScalar: Unicode.Scalar?
        while i < latin.endIndex {
            if let (rule, endIdx) = trie.longestMatch(in: latin, from: i) {
                // Vowel context: a vowel-sign (kar) is only correct when it
                // directly follows a consonant; otherwise emit the independent
                // vowel form (e.g. leading "a" -> আ, but "ka" -> কা).
                var chosenOutput = rule.output
                if layout.vowelSigns[rule.match] != nil,
                   let indep = layout.independentVowels[rule.match],
                   !isPrecededByConsonant(lastEmittedScalar) {
                    chosenOutput = indep
                }
                output += chosenOutput
                lastEmittedScalar = chosenOutput.unicodeScalars.last
                if !rule.alternates.isEmpty {
                    alternates.append(contentsOf: rule.alternates)
                }
                i = endIdx
                lastConsumedEnd = endIdx
            } else {
                // No rule matches at this position. Pass the char through
                // verbatim (latin) so the user sees their typing echoed.
                let ch = String(latin[i])
                output += ch
                lastEmittedScalar = ch.unicodeScalars.last
                i = latin.index(after: i)
            }
        }
        let consumed = String(latin[latin.startIndex..<lastConsumedEnd])
        let remainder = lastConsumedEnd < latin.endIndex
            ? String(latin[lastConsumedEnd..<latin.endIndex])
            : ""
        return Resolution(
            bangla: Normalizer.normalize(output),
            alternates: alternates,
            consumedLatin: consumed,
            remainder: remainder
        )
    }

    /// True when the previously emitted scalar is a Bengali consonant
    /// (so a following vowel key should render as a kar, not an independent vowel).
    private func isPrecededByConsonant(_ scalar: Unicode.Scalar?) -> Bool {
        guard let s = scalar else { return false }
        let v = s.value
        // Bengali consonants U+0995..U+09B9 (ক..হ), plus ড় ঢ় য় and the
        // Assamese-style ra/va (U+09F0..U+09F1).
        if (0x0995...0x09B9).contains(v) { return true }
        if v == 0x09DC || v == 0x09DD || v == 0x09DF { return true }
        if v == 0x09F0 || v == 0x09F1 { return true }
        return false
    }
}

/// Simple trie over rule match strings.
struct RuleTrie: Sendable {
    final class Node: @unchecked Sendable {
        var rule: PhoneticRule?
        var children: [Character: Node] = [:]
    }
    private let root = Node()

    func insert(_ rule: PhoneticRule) {
        var node = root
        for ch in rule.match {
            if let next = node.children[ch] {
                node = next
            } else {
                let next = Node()
                node.children[ch] = next
                node = next
            }
        }
        // Keep the highest-weight rule if there is a collision.
        if let existing = node.rule, existing.weight > rule.weight {
            // no-op
        } else {
            node.rule = rule
        }
    }

    /// Returns the longest matching rule starting at position `from`
    /// in `s`, plus the index just past the match.
    func longestMatch(in s: String, from start: String.Index) -> (PhoneticRule, String.Index)? {
        var node = root
        var i = start
        var best: (PhoneticRule, String.Index)?
        while i < s.endIndex {
            let ch = s[i]
            guard let next = node.children[ch] else { break }
            node = next
            i = s.index(after: i)
            if let r = node.rule {
                best = (r, i)
            }
        }
        return best
    }
}