import Foundation

/// Normalizes Bangla strings to a canonical NFC form and strips
/// artifacts (dotted circles, stray ZWJ) that some stacks produce.
public enum Normalizer {
    public static func normalize(_ input: String) -> String {
        // 1. Foundation NFC composition.
        var result = input.precomposedStringWithCanonicalMapping

        // 2. Remove U+25CC DOTTED CIRCLE that appears as a base for
        //    orphan combining marks. We keep the mark; drop the circle.
        result = result.unicodeScalars
            .filter { $0.value != BanglaRanges.dottedCircle }
            .reduce(into: "") { $0 += String($1) }

        // 3. Collapse runs of ZWJ to at most one between consonants.
        result = collapseZWJRuns(result)

        // 4. Re-run NFC after edits.
        result = result.precomposedStringWithCanonicalMapping

        return result
    }

    /// Returns true if every scalar is in the Bengali block,
    /// Bengali digits, danda/double-danda, ZWJ, ASCII space, or ASCII digits.
    public static func isCanonicalBangla(_ input: String) -> Bool {
        for s in input.unicodeScalars {
            let v = s.value
            if BanglaRanges.isBengaliScalar(s) { continue }
            if v == BanglaRanges.zeroWidthJoiner { continue }
            if v == BanglaRanges.danda || v == BanglaRanges.doubleDanda { continue }
            if s == " " || s == "\n" || s == "\t" { continue }
            if (0x0030...0x0039).contains(v) { continue }   // ASCII digits OK
            return false
        }
        return true
    }

    private static func collapseZWJRuns(_ input: String) -> String {
        var out = ""
        var prevZWJ = false
        for s in input.unicodeScalars {
            if s.value == BanglaRanges.zeroWidthJoiner {
                if prevZWJ { continue }
                prevZWJ = true
                out += String(s)
            } else {
                prevZWJ = false
                out += String(s)
            }
        }
        return out
    }
}