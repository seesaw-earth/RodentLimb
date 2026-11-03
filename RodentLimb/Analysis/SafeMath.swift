// SafeMath.swift — conversions that never trap.
//
// `Int(someDouble)` crashes the app when the value is NaN, infinite or larger than Int.max
// ("Double value cannot be converted to Int…"). Frame counts and bin indices are computed from
// video timestamps and user parameters, so every such conversion in the analyzers goes through
// `Int(safe:)`, which maps NaN to a fallback and clamps everything else to a sane range.

import Foundation

extension Int {
    /// Largest magnitude produced by `Int(safe:)` (≈ 1.1 × 10¹², far above any frame count), so
    /// later `i + n` arithmetic on the result cannot overflow either.
    static let safeLimit = 1 << 40

    /// `Int(d)` without trapping: NaN → `fallback`; ±∞ and huge values are clamped to ±`safeLimit`.
    /// Truncates toward zero like `Int(_:)`; call `.rounded()` / `ceil` / `floor` first as needed.
    @inline(__always)
    init(safe d: Double, fallback: Int = 0) {
        if d.isNaN { self = fallback; return }
        let limit = Double(Int.safeLimit)
        if d >= limit { self = Int.safeLimit; return }
        if d <= -limit { self = -Int.safeLimit; return }
        self = Int(d)
    }
}

extension Double {
    /// The value itself when finite, otherwise `fallback`.
    @inline(__always)
    func finiteOr(_ fallback: Double) -> Double { isFinite ? self : fallback }
}
