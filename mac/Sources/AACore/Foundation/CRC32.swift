// Spec: 13 §3.2 / FLASH-061 (table-driven reflected CRC-32, poly 0xEDB88320) — shared by Flash Sync and ZIP.
import Foundation

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// CRC-32 of `data`. `seed` is the CRC of the preceding bytes (0 to start), so checksums can be chained.
    public static func checksum<D: DataProtocol>(_ data: D, seed: UInt32 = 0) -> UInt32 {
        var c = ~seed
        table.withUnsafeBufferPointer { t in
            for region in data.regions {
                region.withUnsafeBytes { raw in
                    for b in raw { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
                }
            }
        }
        return ~c
    }

    /// CRC-32 over a raw buffer (used by the streaming ZIP writer/reader).
    public static func checksum(_ raw: UnsafeRawBufferPointer, seed: UInt32 = 0) -> UInt32 {
        var c = ~seed
        table.withUnsafeBufferPointer { t in
            for b in raw { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return ~c
    }
}
