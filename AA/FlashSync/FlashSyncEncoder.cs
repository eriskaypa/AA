using System;

namespace AA.FlashSync;

/// <summary>The fountain encoder (spec §8): DEFLATE the payload, split into K chunks, and emit an endless
/// stream of frames — each the XOR of the chunks its seed selects — as Base45 strings ready for a QR code.
/// A manifest is re-shown every 12th frame; the seed counter is deliberately separate from the emit counter
/// so a clean capture decodes at exactly 1.00x.</summary>
public sealed class FlashEncoder
{
    public const int DefaultChunkSize = 900;

    private readonly ManifestFrame _manifest;
    private readonly byte[][] _chunks;
    private readonly int _chunkSize;
    private int _emitted;   // frames shown, drives the manifest cadence
    private uint _seed;     // NEXT seed to use — a SEPARATE counter

    public ManifestFrame Manifest => _manifest;
    public int ChunkCount => _chunks.Length;

    public FlashEncoder(byte[] payload, FrameKind kind, string label, ushort session, int chunkSize = DefaultChunkSize)
    {
        _chunkSize = chunkSize;
        var coded = Deflate.Compress(payload);
        int k = Math.Max(1, (coded.Length + chunkSize - 1) / chunkSize);
        if (k > 65535) throw new InvalidOperationException($"Payload too large for Flash Sync: {k} chunks (max 65535).");
        _chunks = new byte[k][];
        for (int i = 0; i < k; i++)
        {
            var c = new byte[chunkSize];
            int off = i * chunkSize;
            int len = Math.Min(chunkSize, coded.Length - off);
            if (len > 0) Array.Copy(coded, off, c, 0, len);   // last chunk zero-padded
            _chunks[i] = c;
        }
        _manifest = new ManifestFrame
        {
            Session = session,
            CodedBytes = (uint)coded.Length,
            RawBytes = (uint)payload.Length,
            ChunkSize = (ushort)chunkSize,
            ChunkCount = (ushort)k,
            Crc32 = Crc32.Compute(coded),
            Kind = kind,
            Label = label
        };
    }

    /// <summary>The next frame as a Base45 string to render into a QR code. Never terminates — loops until
    /// the user stops.</summary>
    public string Next()
    {
        if (_emitted % 12 == 0)
        {
            _emitted++;
            return Base45.Encode(FlashFrame.EncodeManifest(_manifest));
        }
        _emitted++;
        uint s = _seed;
        _seed++;
        var idx = Fountain.Indices(s, _chunks.Length);
        var body = (byte[])_chunks[idx[0]].Clone();
        for (int k = 1; k < idx.Length; k++)
        {
            var c = _chunks[idx[k]];
            for (int j = 0; j < _chunkSize; j++) body[j] ^= c[j];
        }
        return Base45.Encode(FlashFrame.EncodeData(new DataFrame { Session = _manifest.Session, Seed = s, Payload = body }));
    }

    public static ushort NewSession() => (ushort)Random.Shared.Next(1, 65536);
}
