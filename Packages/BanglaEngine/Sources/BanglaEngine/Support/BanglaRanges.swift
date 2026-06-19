import Foundation

public enum BanglaRanges {
    /// Main Bengali block.
    public static let blockStart: UInt32 = 0x0980
    public static let blockEnd: UInt32   = 0x09FF

    /// Bengali digits.
    public static let digitStart: UInt32 = 0x09E6
    public static let digitEnd: UInt32   = 0x09EF

    /// Signs we treat specially.
    public static let virama: UInt32        = 0x09CD
    public static let zeroWidthJoiner: UInt32 = 0x200C
    public static let dottedCircle: UInt32  = 0x25CC
    public static let danda: UInt32         = 0x0964
    public static let doubleDanda: UInt32   = 0x0965

    public static func isBengaliScalar(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (blockStart...blockEnd).contains(v)
    }

    public static func isBengaliDigit(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (digitStart...digitEnd).contains(v)
    }
}