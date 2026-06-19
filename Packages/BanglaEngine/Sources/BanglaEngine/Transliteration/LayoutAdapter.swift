import Foundation

/// Adapter that turns raw keystrokes into either:
///   - a literal Bangla glyph (fixed layouts), or
///   - a latin phoneme token (phonetic layouts, deferred to PhoneticResolver).
public struct LayoutAdapter: Sendable {
    public let layout: Layout

    public init(layout: Layout) {
        self.layout = layout
    }

    public enum KeystrokeResult: Sendable, Equatable {
        /// Literal Bangla output for fixed layouts.
        case literal(String)
        /// Latin token to be resolved later by PhoneticResolver.
        case phoneme(String)
        /// The keystroke produced no mapping (caller should pass through).
        case passthrough
    }

    public func process(keystroke: String) -> KeystrokeResult {
        switch layout.kind {
        case .fixed:
            if let v = layout.keymap[keystroke] { return .literal(v) }
            return .passthrough
        case .phonetic:
            // Phonetic resolver consumes raw latin; we just forward.
            // Non-letter keystrokes are passthrough.
            if keystroke.unicodeScalars.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "`" || $0 == "." || $0 == "-" || $0 == "~") }) {
                return .phoneme(keystroke)
            }
            return .passthrough
        }
    }
}

private extension Unicode.Scalar {
    var isASCII: Bool { (0...0x7F).contains(value) }
    var isLetter: Bool {
        (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
    }
}