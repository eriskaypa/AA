// ZIP manifest algorithm (spec 01 GF.3.9, GF.4.6): the archive is read with ZipArchive AND its raw local and central
// headers are parsed (to get the method, flags and version-made-by that ZipArchive hides); the manifest and every
// payload are written as separate files. Payloads that are AA formats (data.json, source.json) are masked and
// compared as bytes by the Swift side.
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace WinFixtures;

internal static class ZipInspect
{
    internal sealed record RawEntry(string Name, bool Utf8Flag, int Flags, int Method, uint Crc32, long Uncompressed,
                                    int VersionMadeByHost, uint ExternalAttributes, bool HasDataDescriptor);

    /// <summary>Parses the central directory (Zip64-aware) and each entry's local header flags.</summary>
    public static (List<RawEntry> Entries, bool Zip64, string Comment) Raw(byte[] b)
    {
        int U16(long o) => o + 2 <= b.Length ? b[o] | b[o + 1] << 8 : 0;
        uint U32(long o) => o + 4 <= b.Length ? (uint)(b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24) : 0;
        ulong U64(long o) => U32(o) | (ulong)U32(o + 4) << 32;

        long eocd = -1;
        for (long i = b.Length - 22; i >= Math.Max(0, b.Length - 22 - 65535); i--)
            if (U32(i) == 0x06054B50) { eocd = i; break; }
        if (eocd < 0) throw new InvalidDataException("no end-of-central-directory record");
        long count = U16(eocd + 10);
        long cd = U32(eocd + 16);
        var comment = Encoding.UTF8.GetString(b, (int)eocd + 22, Math.Min(U16(eocd + 20), b.Length - (int)eocd - 22));
        bool zip64 = false;
        if (eocd >= 20 && U32(eocd - 20) == 0x07064B50)
        {
            long z = (long)U64(eocd - 20 + 8);
            if (U32(z) == 0x06064B50) { zip64 = true; count = (long)U64(z + 32); cd = (long)U64(z + 48); }
        }
        var cp437 = CodePage437();
        var list = new List<RawEntry>();
        long p = cd;
        for (long k = 0; k < count; k++)
        {
            if (U32(p) != 0x02014B50) throw new InvalidDataException("bad central header " + k);
            int madeBy = U16(p + 4), flags = U16(p + 8), method = U16(p + 10);
            uint crc = U32(p + 16);
            long uncompressed = U32(p + 24);
            int nameLen = U16(p + 28), extraLen = U16(p + 30), commentLen = U16(p + 32);
            uint ext = U32(p + 38);
            long local = U32(p + 42);
            var nameBytes = new byte[nameLen];
            Array.Copy(b, p + 46, nameBytes, 0, nameLen);
            long e = p + 46 + nameLen, end = e + extraLen;
            while (e + 4 <= end)
            {
                int id = U16(e), size = U16(e + 2);
                if (id == 0x0001)
                {
                    long q = e + 4;
                    if (U32(p + 24) == 0xFFFFFFFF) { uncompressed = (long)U64(q); q += 8; }
                    if (U32(p + 20) == 0xFFFFFFFF) q += 8;
                    if (U32(p + 42) == 0xFFFFFFFF) local = (long)U64(q);
                }
                e += 4 + size;
            }
            bool utf8 = (flags & 0x0800) != 0;
            var name = utf8 || nameBytes.All(x => x < 0x80) ? Encoding.UTF8.GetString(nameBytes) : cp437.GetString(nameBytes);
            int localFlags = U32(local) == 0x04034B50 ? U16(local + 6) : flags;
            list.Add(new RawEntry(name, utf8, flags, method, crc, uncompressed, madeBy >> 8, ext, ((flags | localFlags) & 0x0008) != 0));
            p += 46 + nameLen + extraLen + commentLen;
        }
        return (list, zip64, comment);
    }

    private static Encoding CodePage437()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        return Encoding.GetEncoding(437);
    }

    /// <summary>GF.4.2: `<caseId>.entry.<index>-<name with / → _ and non-[A-Za-z0-9._-] → _>.golden.<ext>`.</summary>
    public static string PayloadName(string caseId, int index, string entryName)
    {
        var sanitized = new string(entryName.Select(c => c == '/' ? '_' :
            (c < 0x80 && (char.IsAsciiLetterOrDigit(c) || c == '.' || c == '_' || c == '-')) ? c : '_').ToArray());
        var dot = entryName.LastIndexOf('.');
        var ext = dot >= 0 ? entryName[(dot + 1)..].ToLowerInvariant() : "";
        if (ext.Length == 0 || !ext.All(char.IsAsciiLetterOrDigit)) ext = "bin";
        return $"{caseId}.entry.{index}-{sanitized}.golden.{ext}";
    }

    public static bool IsAAFormat(string entryName)
    {
        var leaf = entryName.Split('/').Last().ToLowerInvariant();
        return leaf is "data.json" or "source.json" or "settings.json";
    }

    /// <summary>Writes `<id>.zip-manifest.golden.json` and every payload next to it; returns the manifest's path
    /// (recorded as the case output with role <paramref name="role"/>).</summary>
    public static string WriteManifest(CaseRun r, string role, byte[] zip, bool orderSignificant, bool writePayloads = true)
    {
        var (raw, zip64, comment) = Raw(zip);
        var entries = new JsonArray();
        using var archive = new ZipArchive(new MemoryStream(zip), ZipArchiveMode.Read);
        for (int i = 0; i < raw.Count; i++)
        {
            var e = raw[i];
            bool dir = e.Name.EndsWith('/');
            byte[] payload = Array.Empty<byte>();
            if (!dir)
            {
                var ze = archive.Entries.ElementAtOrDefault(i);
                if (ze == null || ze.FullName != e.Name) ze = archive.Entries.FirstOrDefault(x => x.FullName == e.Name);
                if (ze != null)
                {
                    using var s = ze.Open();
                    using var ms = new MemoryStream();
                    s.CopyTo(ms);
                    payload = ms.ToArray();
                }
            }
            string? payloadName = null;
            if (!dir && writePayloads)
            {
                payloadName = PayloadName(r.Id, i + 1, e.Name);
                r.Side(payloadName, payload, mask: IsAAFormat(e.Name));
            }
            entries.Add(new JsonObject
            {
                ["name"] = e.Name,
                ["isDirectory"] = dir,
                ["method"] = e.Method,
                ["flags"] = e.Flags,
                ["utf8NameFlag"] = e.Utf8Flag,
                ["uncompressedSize"] = e.Uncompressed,
                ["crc32"] = $"0x{e.Crc32:X8}",
                ["sha256"] = dir ? "" : Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant(),
                ["payload"] = payloadName,
                ["versionMadeByHost"] = e.VersionMadeByHost,
                ["externalAttributes"] = $"0x{e.ExternalAttributes:X8}",
                ["hasDataDescriptor"] = e.HasDataDescriptor,
            });
        }
        var manifest = new JsonObject
        {
            ["entries"] = entries, ["zip64"] = zip64, ["comment"] = comment, ["orderSignificant"] = orderSignificant,
        };
        return r.Text(role, "zip-manifest", "json", Fx.Expect(manifest), orderSignificant ? "zip-manifest-ordered" : "zip-manifest");
    }
}
