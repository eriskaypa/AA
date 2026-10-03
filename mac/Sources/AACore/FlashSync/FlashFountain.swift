// Spec: 13 §3.4–3.6 / FLASH-063 (xorshift32), FLASH-064 (degree table), FLASH-065 (index derivation);
//       QR_SYNC_PROTOCOL.md §5–§6. Integer-only on purpose: floating point would let two runtimes disagree, and the
//       two sides silently produce garbage if a single index differs. Any change here is a NEW wire version.

/// The deterministic PRNG both sides share (xorshift32, logical shifts on UInt32; a zero seed is remapped).
public struct FlashRandom: Sendable {
    public private(set) var state: UInt32

    public init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    public mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// `next() % n` (n > 0).
    public mutating func next(_ n: Int) -> Int { Int(next() % UInt32(n)) }
}

/// Degree distribution and the seed → chunk-index derivation (the heart of the contract).
public enum FlashFountain {
    /// Below this chunk count frames are plain round-robin (fountain mixing is counterproductive).
    public static let cyclingThreshold = 8

    /// Coarsened Robust Soliton as an integer CDF out of 1024: (threshold, degree).
    public static let degreeCDF: [(threshold: UInt32, degree: Int)] = [
        (84, 1), (554, 2), (718, 3), (800, 4), (851, 5),
        (882, 6), (903, 7), (918, 8), (942, 12), (963, 20),
        (1000, 35), (1024, 60),
    ]

    /// `x = r % 1024`; the first entry with `x < threshold` gives `min(degree, chunkCount)`.
    public static func degree(_ r: UInt32, _ chunkCount: Int) -> Int {
        let x = r % 1024
        for entry in degreeCDF where x < entry.threshold { return min(entry.degree, chunkCount) }
        return min(2, chunkCount)          // unreachable; defensive (parity)
    }

    /// The source chunks a frame with this seed carries, ascending.
    /// K ≤ 8 → round-robin `[seed % K]`; seed < K → the systematic chunk `[seed]`; otherwise a PRNG-drawn set
    /// whose FIRST draw is the degree, duplicates spinning again (capped at `degree × 24` spins).
    public static func indices(_ seed: UInt32, _ chunkCount: Int) -> [Int] {
        guard chunkCount > 0 else { return [] }
        if chunkCount <= cyclingThreshold { return [Int(seed % UInt32(chunkCount))] }
        if seed < UInt32(chunkCount) { return [Int(seed)] }
        var rng = FlashRandom(seed: seed)
        let d = degree(rng.next(), chunkCount)
        var picked = Set<Int>()
        var spins = 0
        while picked.count < d && spins < d * 24 {
            picked.insert(rng.next(chunkCount))
            spins += 1
        }
        if picked.isEmpty { picked.insert(Int(seed % UInt32(chunkCount))) }
        return picked.sorted()
    }
}
