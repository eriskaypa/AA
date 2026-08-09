using System;
using System.Collections.Generic;
using System.Linq;

namespace AA.FlashSync;

/// <summary>The peeling (belief-propagation) fountain decoder (spec §9). Feed it every decoded QR string;
/// it ignores foreign codes and duplicate seeds, and reconstructs the payload once it has enough frames.</summary>
public sealed class FlashDecoder
{
    /// <summary>Ceiling on a transfer's size. A hostile or ECC-mangled manifest can claim up to 4 GB in a
    /// u32; refusing early keeps a corrupt frame from driving a huge allocation. Far above any real payload
    /// (the spec's largest worked example is a 3.1 MB snapshot).</summary>
    public const long MaxPayloadBytes = 64L * 1024 * 1024;

    private ManifestFrame? _manifest;
    private readonly Dictionary<int, byte[]> _solved = new();
    private readonly List<Equation> _pending = new();
    private readonly HashSet<uint> _seenSeeds = new();

    private sealed class Equation
    {
        public HashSet<int> Idx = new();
        public byte[] Body = Array.Empty<byte>();
    }

    public ManifestFrame? Manifest => _manifest;
    public int SolvedCount => _solved.Count;
    public int ChunkCount => _manifest?.ChunkCount ?? 0;
    public bool IsComplete => _manifest != null && _solved.Count == _manifest.ChunkCount;
    public string Label => _manifest?.Label ?? "";

    /// <summary>Feed one decoded QR string. No-op for anything that isn't a valid frame of this transfer.</summary>
    public void Ingest(string text)
    {
        var raw = Base45.Decode(text);
        if (raw == null) return;
        var frame = FlashFrame.Decode(raw);
        if (frame == null) return;

        if (frame is ManifestFrame m)
        {
            if (_manifest == null) { _manifest = m; return; }
            // A different session or CRC means the sender restarted (or the camera wandered onto another
            // screen) — throw everything away rather than mixing two transfers.
            if (m.Session != _manifest.Session || m.Crc32 != _manifest.Crc32) { Reset(); _manifest = m; }
            return;
        }

        var d = (DataFrame)frame;
        if (_manifest == null) return;                              // header not seen yet
        if (d.Session != _manifest.Session) return;
        if (d.Payload.Length != _manifest.ChunkSize) return;
        if (!_seenSeeds.Add(d.Seed)) return;                        // already had this exact frame

        var idx = new HashSet<int>(Fountain.Indices(d.Seed, _manifest.ChunkCount));
        var body = (byte[])d.Payload.Clone();
        foreach (var k in idx.ToList())
            if (_solved.TryGetValue(k, out var sv)) { Xor(body, sv); idx.Remove(k); }

        if (idx.Count == 0) return;                                 // fully redundant
        if (idx.Count == 1) Solve(idx.First(), body);
        else _pending.Add(new Equation { Idx = idx, Body = body });
    }

    private void Solve(int index, byte[] value)
    {
        var queue = new Stack<(int, byte[])>();
        queue.Push((index, value));
        while (queue.Count > 0)
        {
            var (i, v) = queue.Pop();
            if (_solved.ContainsKey(i)) continue;
            _solved[i] = v;
            var still = new List<Equation>(_pending.Count);
            foreach (var eq in _pending)
            {
                if (eq.Idx.Contains(i))
                {
                    Xor(eq.Body, v);
                    eq.Idx.Remove(i);
                    if (eq.Idx.Count == 0) continue;                       // became redundant, drop
                    if (eq.Idx.Count == 1) { queue.Push((eq.Idx.First(), eq.Body)); continue; }
                }
                still.Add(eq);
            }
            _pending.Clear();
            _pending.AddRange(still);
        }
    }

    /// <summary>Reassemble + verify + inflate. Returns the original payload bytes, or null on CRC failure
    /// (which must leave the user's data untouched) or if not yet complete.</summary>
    public byte[]? Finish()
    {
        if (_manifest == null || _solved.Count != _manifest.ChunkCount) return null;
        // Every field here came off a camera through error-correction that can mis-correct, so this whole
        // method is best-effort: it must return null rather than throw. It runs on the capture thread, and
        // an exception at this point is an app crash at the exact moment the user is applying a transfer.
        try
        {
            int k = _manifest.ChunkCount, cs = _manifest.ChunkSize;
            long total = (long)k * cs;
            if (total <= 0 || total > MaxPayloadBytes) return null;
            var coded = new byte[total];
            for (int i = 0; i < k; i++)
            {
                if (!_solved.TryGetValue(i, out var chunk) || chunk.Length != cs) return null;
                Array.Copy(chunk, 0, coded, (long)i * cs, cs);
            }
            long codedBytes = _manifest.CodedBytes;
            if (codedBytes <= 0 || codedBytes > coded.Length) return null;   // u32 -> int would overflow
            coded = coded[..(int)codedBytes];
            if (Crc32.Compute(coded) != _manifest.Crc32) return null;   // corrupted — report, change nothing
            long raw = _manifest.RawBytes;
            if (raw <= 0 || raw > MaxPayloadBytes) return null;         // don't allocate on a hostile u32
            return Deflate.Inflate(coded, (int)raw);
        }
        catch { return null; }
    }

    private void Reset()
    {
        _solved.Clear();
        _pending.Clear();
        _seenSeeds.Clear();
    }

    private static void Xor(byte[] a, byte[] b)
    {
        for (int i = 0; i < a.Length; i++) a[i] ^= b[i];
    }
}
