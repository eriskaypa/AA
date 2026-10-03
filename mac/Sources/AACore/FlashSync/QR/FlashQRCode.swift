// Spec: 13 §3.10, §6.3 / FLASH-071 (alphanumeric mode, ECC L requested and boosted when it fits, smallest version,
//       automatic mask by minimum penalty, Reed-Solomon over GF(256)/0x11D correct for blocks that start with many
//       zero codewords — the zero-padded tail chunk that broke QRCoder).
// Pure-Swift port of Project Nayuki's QR Code generator library (https://www.nayuki.io/page/qr-code-generator-library,
// MIT License, Copyright (c) Project Nayuki). Follows `qrcodegen.py` 1.8.0 step for step so that Mac frames are
// module-for-module identical to the Windows ones (Net.Codecrete.QrCodeGenerator is a port of the same library).

/// Error-correction level. `ordinal` indexes the capacity tables; `formatBits` goes into the format information.
public enum FlashQREcc: Int, Sendable, CaseIterable, Comparable {
    case low = 0, medium, quartile, high

    public var formatBits: Int {
        switch self {
        case .low: return 1
        case .medium: return 0
        case .quartile: return 3
        case .high: return 2
        }
    }

    public static func < (a: FlashQREcc, b: FlashQREcc) -> Bool { a.rawValue < b.rawValue }
}

public enum FlashQRError: Error, Equatable, Sendable {
    /// "Data length = {bits} bits, Max capacity = {capacity} bits" / "Segment too long".
    case dataTooLong(String)
}

/// An immutable QR Code symbol (Model 2, versions 1…40).
public struct FlashQRCode: Sendable, Equatable {
    public static let minVersion = 1
    public static let maxVersion = 40

    public let version: Int
    /// Modules per side: version × 4 + 17.
    public let size: Int
    public let errorCorrectionLevel: FlashQREcc
    public let mask: Int
    /// Row-major, `true` = dark.
    public let modules: [Bool]
    /// The final codewords (data + ECC, interleaved) — for the CIQRCodeDescriptor cross-check.
    public let codewords: [UInt8]

    /// True when (x, y) is dark; false outside the symbol.
    public func module(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < size && y >= 0 && y < size && modules[y * size + x]
    }

    // MARK: High / mid level

    /// Nayuki `encode_text(text, ecl)`.
    public static func encodeText(_ text: String, ecl: FlashQREcc) throws(FlashQRError) -> FlashQRCode {
        try encodeSegments(FlashQRSegment.makeSegments(text), ecl: ecl)
    }

    /// Nayuki `encode_segments`: the smallest version in range that fits; ECC boosted while it still fits (when
    /// `boostEcl`); terminator, bit padding and 0xEC/0x11 pad bytes; `mask` -1 = automatic.
    public static func encodeSegments(_ segs: [FlashQRSegment], ecl requested: FlashQREcc, minVersion: Int = 1,
                                      maxVersion: Int = 40, mask: Int = -1,
                                      boostEcl: Bool = true) throws(FlashQRError) -> FlashQRCode {
        precondition(1 <= minVersion && minVersion <= maxVersion && maxVersion <= 40 && (-1 ... 7).contains(mask))
        var version = minVersion
        var dataUsedBits = 0
        while true {
            let capacity = numDataCodewords(version, requested) * 8
            let used = FlashQRSegment.totalBits(segs, version: version)
            if let used, used <= capacity { dataUsedBits = used; break }
            if version >= maxVersion {
                if let used { throw .dataTooLong("Data length = \(used) bits, Max capacity = \(capacity) bits") }
                throw .dataTooLong("Segment too long")
            }
            version += 1
        }
        var ecl = requested
        for newEcl in [FlashQREcc.medium, .quartile, .high] where boostEcl && dataUsedBits <= numDataCodewords(version, newEcl) * 8 {
            ecl = newEcl
        }

        var bb = FlashQRBitBuffer()
        for seg in segs {
            bb.append(seg.mode.modeBits, bits: 4)
            bb.append(seg.numChars, bits: seg.mode.charCountBits(version: version))
            bb.append(contentsOf: seg.data)
        }
        let capacity = numDataCodewords(version, ecl) * 8
        bb.append(0, bits: min(4, capacity - bb.count))
        bb.append(0, bits: (8 - bb.count % 8) % 8)
        var pad = 0xEC
        while bb.count < capacity {
            bb.append(pad, bits: 8)
            pad ^= 0xEC ^ 0x11
        }
        var data = [UInt8](repeating: 0, count: bb.count / 8)
        for (i, bit) in bb.bits.enumerated() where bit { data[i >> 3] |= UInt8(1 << (7 - (i & 7))) }
        return FlashQRCode(version: version, ecl: ecl, dataCodewords: data, mask: mask)
    }

    // MARK: Low level

    /// Nayuki constructor: draws function patterns, adds ECC and interleaves, draws the codewords, then applies the
    /// given mask (0…7) or the one with the lowest penalty (-1; the lowest index wins ties).
    public init(version: Int, ecl: FlashQREcc, dataCodewords: [UInt8], mask requestedMask: Int) {
        precondition((1 ... 40).contains(version) && (-1 ... 7).contains(requestedMask))
        precondition(dataCodewords.count == FlashQRCode.numDataCodewords(version, ecl))
        var g = FlashQRGrid(version: version, ecl: ecl)
        g.drawFunctionPatterns()
        let all = g.addEccAndInterleave(dataCodewords)
        g.drawCodewords(all)
        var msk = requestedMask
        if msk == -1 {
            var minPenalty = Int.max
            for i in 0 ..< 8 {
                g.applyMask(i)
                g.drawFormatBits(i)
                let p = g.penaltyScore()
                if p < minPenalty { msk = i; minPenalty = p }
                g.applyMask(i)                                  // XOR undoes the mask
            }
        }
        g.applyMask(msk)
        g.drawFormatBits(msk)
        self.version = version
        size = g.size
        errorCorrectionLevel = ecl
        mask = msk
        modules = g.modules
        codewords = all
    }

    // MARK: Capacity

    static let eccCodewordsPerBlock: [[Int]] = [
        // 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
        [-1,  7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Low
        [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],  // Medium
        [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Quartile
        [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // High
    ]

    static let numErrorCorrectionBlocks: [[Int]] = [
        // 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
        [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,  4,  4,  4,  4,  6,  6,  6,  6,  7,  8,  8,  9,  9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],  // Low
        [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5,  5,  8,  9,  9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],  // Medium
        [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8,  8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],  // Quartile
        [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],  // High
    ]

    /// Data modules available after function patterns (incl. remainder bits).
    public static func numRawDataModules(_ ver: Int) -> Int {
        var result = (16 * ver + 128) * ver + 64
        if ver >= 2 {
            let numAlign = ver / 7 + 2
            result -= (25 * numAlign - 10) * numAlign - 55
            if ver >= 7 { result -= 36 }
        }
        return result
    }

    /// 8-bit data codewords available at a version and ECC level.
    public static func numDataCodewords(_ ver: Int, _ ecl: FlashQREcc) -> Int {
        numRawDataModules(ver) / 8 - eccCodewordsPerBlock[ecl.rawValue][ver] * numErrorCorrectionBlocks[ecl.rawValue][ver]
    }

    // MARK: Reed-Solomon over GF(2^8 / 0x11D)

    /// The generator polynomial of a degree (coefficients high to low, leading 1 omitted).
    public static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        precondition(degree >= 1 && degree <= 255)
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0 ..< degree {
            for j in 0 ..< result.count {
                result[j] = reedSolomonMultiply(result[j], root)
                if j + 1 < result.count { result[j] ^= result[j + 1] }
            }
            root = reedSolomonMultiply(root, 0x02)
        }
        return result
    }

    /// The remainder of `data · x^degree` divided by the divisor — the ECC codewords.
    public static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for b in data {
            let factor = b ^ result[0]
            result.removeFirst()
            result.append(0)
            for i in 0 ..< result.count { result[i] ^= reedSolomonMultiply(divisor[i], factor) }
        }
        return result
    }

    /// Russian-peasant multiplication modulo 0x11D.
    public static func reedSolomonMultiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        var i = 7
        while i >= 0 {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((Int(y) >> i) & 1) * Int(x)
            i -= 1
        }
        return UInt8(z)
    }
}

/// The mutable drawing state of the Nayuki constructor (modules + the function-module mask).
struct FlashQRGrid {
    let version: Int
    let size: Int
    let ecl: FlashQREcc
    var modules: [Bool]
    var isFunction: [Bool]

    init(version: Int, ecl: FlashQREcc) {
        self.version = version
        self.ecl = ecl
        size = version * 4 + 17
        modules = [Bool](repeating: false, count: size * size)
        isFunction = [Bool](repeating: false, count: size * size)
    }

    private mutating func setFunction(_ x: Int, _ y: Int, _ dark: Bool) {
        modules[y * size + x] = dark
        isFunction[y * size + x] = true
    }

    mutating func drawFunctionPatterns() {
        for i in 0 ..< size {                                           // timing patterns
            setFunction(6, i, i % 2 == 0)
            setFunction(i, 6, i % 2 == 0)
        }
        drawFinder(3, 3)
        drawFinder(size - 4, 3)
        drawFinder(3, size - 4)
        let pos = alignmentPositions()
        let n = pos.count
        for i in 0 ..< n {
            for j in 0 ..< n where !(i == 0 && j == 0 || i == 0 && j == n - 1 || i == n - 1 && j == 0) {
                drawAlignment(pos[i], pos[j])
            }
        }
        drawFormatBits(0)                                               // dummy; overwritten later
        drawVersion()
    }

    mutating func drawFormatBits(_ mask: Int) {
        let data = ecl.formatBits << 3 | mask
        var rem = data
        for _ in 0 ..< 10 { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
        let bits = (data << 10 | rem) ^ 0x5412
        func bit(_ i: Int) -> Bool { (bits >> i) & 1 != 0 }
        for i in 0 ... 5 { setFunction(8, i, bit(i)) }
        setFunction(8, 7, bit(6))
        setFunction(8, 8, bit(7))
        setFunction(7, 8, bit(8))
        for i in 9 ..< 15 { setFunction(14 - i, 8, bit(i)) }
        for i in 0 ..< 8 { setFunction(size - 1 - i, 8, bit(i)) }
        for i in 8 ..< 15 { setFunction(8, size - 15 + i, bit(i)) }
        setFunction(8, size - 8, true)                                  // always dark
    }

    private mutating func drawVersion() {
        guard version >= 7 else { return }
        var rem = version
        for _ in 0 ..< 12 { rem = (rem << 1) ^ ((rem >> 11) * 0x1F25) }
        let bits = version << 12 | rem
        for i in 0 ..< 18 {
            let b = (bits >> i) & 1 != 0
            let a = size - 11 + i % 3, c = i / 3
            setFunction(a, c, b)
            setFunction(c, a, b)
        }
    }

    private mutating func drawFinder(_ x: Int, _ y: Int) {
        for dy in -4 ... 4 {
            for dx in -4 ... 4 {
                let dist = max(abs(dx), abs(dy))
                let xx = x + dx, yy = y + dy
                if xx >= 0 && xx < size && yy >= 0 && yy < size { setFunction(xx, yy, dist != 2 && dist != 4) }
            }
        }
    }

    private mutating func drawAlignment(_ x: Int, _ y: Int) {
        for dy in -2 ... 2 {
            for dx in -2 ... 2 { setFunction(x + dx, y + dy, max(abs(dx), abs(dy)) != 1) }
        }
    }

    func alignmentPositions() -> [Int] {
        if version == 1 { return [] }
        let numAlign = version / 7 + 2
        let step = version == 32 ? 26 : (version * 4 + numAlign * 2 + 1) / (numAlign * 2 - 2) * 2
        var result: [Int] = (0 ..< numAlign - 1).map { size - 7 - $0 * step }
        result.append(6)
        return result.reversed()
    }

    func addEccAndInterleave(_ data: [UInt8]) -> [UInt8] {
        let numBlocks = FlashQRCode.numErrorCorrectionBlocks[ecl.rawValue][version]
        let blockEccLen = FlashQRCode.eccCodewordsPerBlock[ecl.rawValue][version]
        let rawCodewords = FlashQRCode.numRawDataModules(version) / 8
        let numShortBlocks = numBlocks - rawCodewords % numBlocks
        let shortBlockLen = rawCodewords / numBlocks
        let divisor = FlashQRCode.reedSolomonDivisor(degree: blockEccLen)
        var blocks: [[UInt8]] = []
        var k = 0
        for i in 0 ..< numBlocks {
            let len = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1)
            let dat = Array(data[k ..< k + len])
            k += len
            let ecc = FlashQRCode.reedSolomonRemainder(dat, divisor: divisor)
            var block = dat
            if i < numShortBlocks { block.append(0) }                   // padding byte, skipped below
            block += ecc
            blocks.append(block)
        }
        var result: [UInt8] = []
        result.reserveCapacity(rawCodewords)
        for i in 0 ..< blocks[0].count {
            for (j, block) in blocks.enumerated() where i != shortBlockLen - blockEccLen || j >= numShortBlocks {
                result.append(block[i])
            }
        }
        return result
    }

    mutating func drawCodewords(_ data: [UInt8]) {
        var i = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vert in 0 ..< size {
                for j in 0 ..< 2 {
                    let x = right - j
                    let upward = (right + 1) & 2 == 0
                    let y = upward ? size - 1 - vert : vert
                    if !isFunction[y * size + x] && i < data.count * 8 {
                        modules[y * size + x] = (data[i >> 3] >> (7 - (i & 7))) & 1 != 0
                        i += 1
                    }
                }
            }
            right -= 2
        }
    }

    mutating func applyMask(_ mask: Int) {
        for y in 0 ..< size {
            for x in 0 ..< size {
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (x / 3 + y / 2) % 2 == 0
                case 5: invert = x * y % 2 + x * y % 3 == 0
                case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                }
                let p = y * size + x
                if invert && !isFunction[p] { modules[p].toggle() }
            }
        }
    }

    // MARK: Penalty (N1 = 3, N2 = 3, N3 = 40, N4 = 10; Nayuki's finder-pattern run history)

    func penaltyScore() -> Int {
        var result = 0
        for y in 0 ..< size { result += linePenalty { modules[y * size + $0] } }
        for x in 0 ..< size { result += linePenalty { modules[$0 * size + x] } }
        for y in 0 ..< size - 1 {
            for x in 0 ..< size - 1 {
                let c = modules[y * size + x]
                if c == modules[y * size + x + 1] && c == modules[(y + 1) * size + x] && c == modules[(y + 1) * size + x + 1] {
                    result += 3
                }
            }
        }
        let dark = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = size * size
        let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        result += k * 10
        return result
    }

    private func linePenalty(_ at: (Int) -> Bool) -> Int {
        var result = 0
        var runColor = false
        var run = 0
        var history = [Int](repeating: 0, count: 7)
        for i in 0 ..< size {
            let c = at(i)
            if c == runColor {
                run += 1
                if run == 5 { result += 3 } else if run > 5 { result += 1 }
            } else {
                addHistory(run, &history)
                if !runColor { result += countPatterns(history) * 40 }
                runColor = c
                run = 1
            }
        }
        // terminate and count
        if runColor {
            addHistory(run, &history)
            run = 0
        }
        run += size
        addHistory(run, &history)
        result += countPatterns(history) * 40
        return result
    }

    private func addHistory(_ length: Int, _ history: inout [Int]) {
        var len = length
        if history[0] == 0 { len += size }                              // light border before the first run
        history.removeLast()
        history.insert(len, at: 0)
    }

    private func countPatterns(_ h: [Int]) -> Int {
        let n = h[1]
        let core = n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n
        return (core && h[0] >= n * 4 && h[6] >= n ? 1 : 0) + (core && h[6] >= n * 4 && h[0] >= n ? 1 : 0)
    }
}
