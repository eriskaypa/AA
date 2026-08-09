using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace AA.FlashSync;

// Windows/PC side of AA "Flash Sync" — the wire-exact port of the fountain-coded QR transfer defined by
// QR_SYNC_PROTOCOL.md (wire version 1, magic "AAQ\x01"). Every constant, the PRNG, the degree table, the
// index derivation and the framing MUST match the shipping iOS side byte-for-byte, or the two produce
// garbage. This file is verified against the spec's test vectors in the headless harness.

/// <summary>Base45 (RFC 9285) — QR's alphanumeric charset, so the QR encoder packs it densely.</summary>
public static class Base45
{
    private const string Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    private static readonly int[] Rev = BuildRev();
    private static int[] BuildRev()
    {
        var r = new int[128];
        for (int i = 0; i < r.Length; i++) r[i] = -1;
        for (int i = 0; i < Alphabet.Length; i++) r[Alphabet[i]] = i;
        return r;
    }

    public static string Encode(byte[] data)
    {
        var sb = new System.Text.StringBuilder();
        int i = 0;
        for (; i + 1 < data.Length; i += 2)
        {
            int n = data[i] * 256 + data[i + 1];
            sb.Append(Alphabet[n % 45]);
            sb.Append(Alphabet[(n / 45) % 45]);
            sb.Append(Alphabet[n / 45 / 45]);
        }
        if (i < data.Length)
        {
            int a = data[i];
            sb.Append(Alphabet[a % 45]);
            sb.Append(Alphabet[a / 45]);
        }
        return sb.ToString();
    }

    /// <summary>Decode Base45; returns null on any invalid input (that is how the decoder ignores QR
    /// codes that belong to something else entirely).</summary>
    public static byte[]? Decode(string s)
    {
        if (s.Length % 3 == 1) return null;   // one trailing character is invalid
        var outp = new List<byte>(s.Length / 3 * 2 + 1);
        int i = 0;
        for (; i + 2 < s.Length; i += 3)
        {
            int c0 = Val(s[i]), c1 = Val(s[i + 1]), c2 = Val(s[i + 2]);
            if (c0 < 0 || c1 < 0 || c2 < 0) return null;
            int n = c0 + c1 * 45 + c2 * 45 * 45;
            if (n > 0xFFFF) return null;
            outp.Add((byte)(n >> 8));
            outp.Add((byte)(n & 0xFF));
        }
        if (i + 1 < s.Length)   // exactly two trailing characters
        {
            int c0 = Val(s[i]), c1 = Val(s[i + 1]);
            if (c0 < 0 || c1 < 0) return null;
            int n = c0 + c1 * 45;
            if (n > 0xFF) return null;
            outp.Add((byte)n);
        }
        return outp.ToArray();
    }

    private static int Val(char c) => c < 128 ? Rev[c] : -1;
}

/// <summary>CRC-32/ISO-HDLC (IEEE 802.3 / zip / PNG): reflected, poly 0xEDB88320, init/final 0xFFFFFFFF.</summary>
public static class Crc32
{
    private static readonly uint[] Table = BuildTable();
    private static uint[] BuildTable()
    {
        var t = new uint[256];
        for (uint i = 0; i < 256; i++)
        {
            uint c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            t[i] = c;
        }
        return t;
    }

    public static uint Compute(byte[] data)
    {
        uint c = 0xFFFFFFFFu;
        foreach (var b in data) c = Table[(c ^ b) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }
}

/// <summary>Deterministic xorshift32 — both sides must produce byte-identical streams (integer-only).</summary>
public struct QrRandom
{
    private uint s;
    public QrRandom(uint seed) { s = seed == 0 ? 0x9E3779B9u : seed; }
    public uint Next()
    {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    }
    public int Next(int n) => (int)(Next() % (uint)n);
}

/// <summary>Raw DEFLATE (RFC 1951 — no zlib/gzip wrapper). Matches iOS COMPRESSION_ZLIB raw stream.</summary>
public static class Deflate
{
    public static byte[] Compress(byte[] data)
    {
        using var ms = new MemoryStream();
        using (var ds = new DeflateStream(ms, CompressionLevel.Optimal, leaveOpen: true))
            ds.Write(data, 0, data.Length);
        return ms.ToArray();
    }

    public static byte[] Inflate(byte[] coded, int rawLength)
    {
        using var ms = new MemoryStream(coded);
        using var ds = new DeflateStream(ms, CompressionMode.Decompress);
        var outp = new byte[rawLength];
        int off = 0;
        while (off < rawLength)
        {
            int read = ds.Read(outp, off, rawLength - off);
            if (read == 0) break;
            off += read;
        }
        if (off != rawLength) throw new InvalidDataException($"Inflate produced {off} bytes, expected {rawLength}.");
        return outp;
    }
}

/// <summary>The fountain degree distribution + index derivation — the heart of the contract.</summary>
public static class Fountain
{
    public const int CyclingThreshold = 8;

    // (cumulative threshold out of 1024, degree) — a coarsened Robust Soliton, hardcoded so floating-point
    // differences between runtimes cannot desynchronise the two implementations.
    private static readonly (uint Threshold, int Degree)[] DegreeCdf =
    {
        (84,1), (554,2), (718,3), (800,4), (851,5),
        (882,6), (903,7), (918,8), (942,12), (963,20),
        (1000,35), (1024,60)
    };

    public static int Degree(uint r, int chunkCount)
    {
        uint x = r % 1024;
        foreach (var (threshold, d) in DegreeCdf)
            if (x < threshold) return Math.Min(d, chunkCount);
        return Math.Min(2, chunkCount);   // unreachable; defensive
    }

    /// <summary>The source-chunk indices XOR'd into the frame carrying <paramref name="seed"/>. Ascending.</summary>
    public static int[] Indices(uint seed, int chunkCount)
    {
        if (chunkCount <= 0) return Array.Empty<int>();
        // Small payloads: plain round-robin, no mixing.
        if (chunkCount <= CyclingThreshold) return new[] { (int)(seed % (uint)chunkCount) };
        // Systematic prefix: the first K seeds are the plain chunks.
        if (seed < (uint)chunkCount) return new[] { (int)seed };

        var rng = new QrRandom(seed);
        int degree = Degree(rng.Next(), chunkCount);   // the FIRST Next() is the degree draw
        var picked = new SortedSet<int>();
        int spins = 0;
        while (picked.Count < degree && spins < degree * 24)
        {
            picked.Add(rng.Next(chunkCount));
            spins++;
        }
        if (picked.Count == 0) picked.Add((int)(seed % (uint)chunkCount));
        return picked.ToArray();   // ASCENDING
    }
}

public enum FrameKind { ChangeSet = 0, FullSnapshot = 1 }

public sealed class ManifestFrame
{
    public ushort Session;
    public uint CodedBytes;
    public uint RawBytes;
    public ushort ChunkSize;
    public ushort ChunkCount;
    public uint Crc32;
    public FrameKind Kind;
    public string Label = "";
}

public sealed class DataFrame
{
    public ushort Session;
    public uint Seed;
    public byte[] Payload = Array.Empty<byte>();
}

/// <summary>Binary frame encode/decode. All multi-byte integers big-endian. Magic "AAQ" + version 1.</summary>
public static class FlashFrame
{
    private static readonly byte[] Magic = { 0x41, 0x41, 0x51 };  // "AAQ"
    private const byte Version = 0x01;
    private const byte TypeManifest = 0x00;
    private const byte TypeData = 0x01;

    public static byte[] EncodeManifest(ManifestFrame m)
    {
        var label = System.Text.Encoding.UTF8.GetBytes(m.Label);
        if (label.Length > 120) label = label.Take(120).ToArray();
        var b = new List<byte>(25 + label.Length);
        b.AddRange(Magic); b.Add(Version); b.Add(TypeManifest);
        U16(b, m.Session);
        U32(b, m.CodedBytes);
        U32(b, m.RawBytes);
        U16(b, m.ChunkSize);
        U16(b, m.ChunkCount);
        U32(b, m.Crc32);
        b.Add((byte)m.Kind);
        b.Add((byte)label.Length);
        b.AddRange(label);
        return b.ToArray();
    }

    public static byte[] EncodeData(DataFrame d)
    {
        var b = new List<byte>(11 + d.Payload.Length);
        b.AddRange(Magic); b.Add(Version); b.Add(TypeData);
        U16(b, d.Session);
        U32(b, d.Seed);
        b.AddRange(d.Payload);
        return b.ToArray();
    }

    /// <summary>Decode a raw frame. Returns a <see cref="ManifestFrame"/>, a <see cref="DataFrame"/>, or
    /// null when the bytes are not ours / malformed.</summary>
    public static object? Decode(byte[] f)
    {
        if (f.Length < 5) return null;
        if (f[0] != Magic[0] || f[1] != Magic[1] || f[2] != Magic[2] || f[3] != Version) return null;
        byte type = f[4];
        try
        {
            if (type == TypeManifest)
            {
                if (f.Length < 25) return null;
                // Everything below arrives from a camera, through QR error-correction that can silently
                // mis-correct. Validate before trusting: chunkCount=0 would make the decoder report a
                // COMPLETED transfer before a single data frame arrived (solved.Count == 0 == chunkCount)
                // and hand an empty payload to apply. iOS rejects the frame here (RQRSync.swift:331).
                if (RU16(f, 15) == 0 || RU16(f, 17) == 0) return null;
                if (f[23] > (byte)FrameKind.FullSnapshot) return null;   // unknown kind, not a blind cast
                var m = new ManifestFrame
                {
                    Session = RU16(f, 5),
                    CodedBytes = RU32(f, 7),
                    RawBytes = RU32(f, 11),
                    ChunkSize = RU16(f, 15),
                    ChunkCount = RU16(f, 17),
                    Crc32 = RU32(f, 19),
                    Kind = (FrameKind)f[23],
                };
                int labelLen = f[24];
                if (f.Length < 25 + labelLen) return null;
                m.Label = System.Text.Encoding.UTF8.GetString(f, 25, labelLen);
                return m;
            }
            if (type == TypeData)
            {
                if (f.Length <= 11) return null;   // must carry at least one payload byte (iOS: > 11)
                return new DataFrame
                {
                    Session = RU16(f, 5),
                    Seed = RU32(f, 7),
                    Payload = f.Skip(11).ToArray()
                };
            }
        }
        catch { return null; }
        return null;
    }

    private static void U16(List<byte> b, ushort v) { b.Add((byte)(v >> 8)); b.Add((byte)v); }
    private static void U32(List<byte> b, uint v) { b.Add((byte)(v >> 24)); b.Add((byte)(v >> 16)); b.Add((byte)(v >> 8)); b.Add((byte)v); }
    private static ushort RU16(byte[] f, int o) => (ushort)((f[o] << 8) | f[o + 1]);
    private static uint RU32(byte[] f, int o) => ((uint)f[o] << 24) | ((uint)f[o + 1] << 16) | ((uint)f[o + 2] << 8) | f[o + 3];
}
