// HalfFloat.swift — half-precision conversion without Swift's Float16 type (unavailable on Intel Macs).
// Foundation-free; tested against NumPy on Linux.

/// IEEE 754 half → single precision (works on Intel and Apple silicon).
enum HalfFloat {
    @inline(__always) static func float(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = Int((h >> 10) & 0x1F)
        var mant = UInt32(h & 0x03FF)
        let bits: UInt32
        if exp == 0 {
            if mant == 0 {
                bits = sign
            } else {
                // Subnormal: normalise.
                var e = -1
                repeat { e += 1; mant <<= 1 } while mant & 0x0400 == 0
                mant &= 0x03FF
                bits = sign | UInt32(127 - 15 - e) << 23 | mant << 13
            }
        } else if exp == 0x1F {
            bits = sign | 0x7F80_0000 | mant << 13
        } else {
            bits = sign | UInt32(exp - 15 + 127) << 23 | mant << 13
        }
        return Float(bitPattern: bits)
    }
}
