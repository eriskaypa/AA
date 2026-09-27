using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.FlashSync;

// ============================================================================
//  Flash Sync conformance + interop CLI.
//
//    vectors                                   run every vector in QR_SYNC_PROTOCOL.md
//    encode <payload> <out.frames> <n> <kind> <label> [seed]
//                                              write n QR strings, one per line
//    decode <in.frames> <out.payload>          reassemble; exit 1 if incomplete/corrupt
//    cs-build <current> <baseline> <cur-settings> <base-settings> <out>
//    cs-apply <data> <settings> <changeset> <out-data> <out-settings>
//
//  The frame files are the interop surface: the Swift twin writes and reads the
//  same format, so each side can decode what the other flashed.
// ============================================================================

static int Fail(string m) { Console.Error.WriteLine("FAIL: " + m); return 1; }
static string Hex(byte[] b) => Convert.ToHexString(b);

switch (args.FirstOrDefault())
{
    case "vectors": return Vectors();
    case "encode":  return Encode(args);
    case "decode":  return Decode(args);
    case "cs-build": return CsBuild(args);
    case "cs-apply": return CsApply(args);
    case "snap-build": return SnapBuild(args);
    case "snap-apply": return SnapApply(args);
    default: Console.Error.WriteLine("usage: vectors | encode | decode | cs-build | cs-apply"); return 2;
}

// ---------------------------------------------------------------------------
static int Vectors()
{
    int bad = 0;
    void Check(bool ok, string what) { Console.WriteLine($"  {(ok ? "✓" : "✗")} {what}"); if (!ok) bad++; }

    Console.WriteLine("Base45");
    Check(Base45.Encode(Array.Empty<byte>()) == "", "\"\" -> \"\"");
    Check(Base45.Encode(Encoding.ASCII.GetBytes("A")) == "K1", "\"A\" -> K1");
    Check(Base45.Encode(Encoding.ASCII.GetBytes("AB")) == "BB8", "\"AB\" -> BB8");
    Check(Base45.Encode(Encoding.ASCII.GetBytes("Hello!!")) == "%69 VD92EX0", "\"Hello!!\"");
    Check(Base45.Encode(Encoding.ASCII.GetBytes("base-45")) == "UJCLQE7W581", "\"base-45\"");
    Check(Base45.Encode(new byte[] { 0, 1, 0xFE, 0xFF }) == "100TAW", "00 01 FE FF -> 100TAW");
    Check(Base45.Decode("HELLO WORLD!") == null, "foreign text rejected");

    Console.WriteLine("CRC-32");
    Check(Crc32.Compute(Array.Empty<byte>()) == 0x00000000, "\"\"");
    Check(Crc32.Compute(Encoding.ASCII.GetBytes("123456789")) == 0xCBF43926, "\"123456789\" = CBF43926");
    Check(Crc32.Compute(Encoding.ASCII.GetBytes("AA flash sync")) == 0xCD539EA5, "\"AA flash sync\"");

    Console.WriteLine("xorshift32");
    void Seq(uint seed, uint[] want)
    {
        var r = new QrRandom(seed);
        var got = Enumerable.Range(0, 8).Select(_ => r.Next()).ToArray();
        Check(got.SequenceEqual(want), $"seed {seed}");
    }
    Seq(1, new uint[] { 270369, 67634689, 2647435461, 307599695, 2398689233, 745495504, 632435482, 435756210 });
    Seq(12345, new uint[] { 3336926330, 1697253807, 2816511904, 1955480042, 718842323, 3283620450, 4285686168, 3680911160 });
    Seq(0, new uint[] { 1359758873, 3761132862, 2075758394, 25405621, 3862129951, 4186559031, 3122997712, 4244368831 });

    Console.WriteLine("degree");
    foreach (var (r, deg) in new (uint, int)[] { (0,1),(83,1),(84,2),(553,2),(554,3),(1023,60),(1024,1),(4294967295,60) })
        Check(Fountain.Degree(r, 1000) == deg, $"r={r} -> {deg}");

    Console.WriteLine("indices (the ten rows that everything else rests on)");
    foreach (var (s, k, want) in new (uint, int, int[])[] {
        (0,5,new[]{0}), (3,5,new[]{3}), (7,5,new[]{2}), (99,5,new[]{4}),
        (0,100,new[]{0}), (99,100,new[]{99}), (100,100,new[]{34}), (101,100,new[]{47}),
        (5000,100,new[]{64,90}), (65535,100,new[]{50}) })
        Check(Fountain.Indices(s, k).SequenceEqual(want), $"seed={s} K={k} -> [{string.Join(",", want)}]");

    Console.WriteLine("frames");
    var m = new ManifestFrame { Session = 0x1234, CodedBytes = 1129, RawBytes = 3075, ChunkSize = 900,
                                ChunkCount = 2, Crc32 = 0x3D3150F8, Kind = FrameKind.ChangeSet, Label = "1 equipment" };
    Check(Hex(FlashFrame.EncodeManifest(m)) == "414151010012340000046900000C03038400023D3150F8000B312065717569706D656E74",
          "manifest bytes");
    Check(Base45.Encode(FlashFrame.EncodeManifest(m)) == "AB8$AAI00$P6400FCDC006H0.UGXC0OA6%FVUI1D44KFE$EDF$DG/D",
          "manifest QR text");
    var d = new DataFrame { Session = 0x1234, Seed = 7, Payload = Enumerable.Range(0, 16).Select(i => (byte)i).ToArray() };
    Check(Hex(FlashFrame.EncodeData(d)) == "4141510101123400000007000102030405060708090A0B0C0D0E0F", "data bytes");
    Check(Base45.Encode(FlashFrame.EncodeData(d)) == "AB8$AA460$P6000$*0X507H0QS00+0J61%H1CT1F0", "data QR text");

    Console.WriteLine("DEFLATE (must inflate the iOS stream; must be RAW, not zlib)");
    var iosDeflate = Convert.FromHexString("73748401273870860300");
    var raw = Convert.FromHexString("414141414141414141414242424242424242424243434343434343434343");
    Check(Deflate.Inflate(iosDeflate, raw.Length).SequenceEqual(raw), "inflates the iOS-produced stream");
    var ours = Deflate.Compress(raw);
    Check(ours.Length > 0 && ours[0] != 0x78, $"our output is raw DEFLATE (first byte {ours[0]:X2}, not 78)");

    Console.WriteLine(bad == 0 ? "\nALL VECTORS PASS" : $"\n{bad} VECTOR(S) FAILED");
    return bad == 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------
static int Encode(string[] a)
{
    var payload = File.ReadAllBytes(a[1]);
    int n = int.Parse(a[3]);
    var kind = a[4] == "snapshot" ? FrameKind.FullSnapshot : FrameKind.ChangeSet;
    ushort session = a.Length > 6 ? ushort.Parse(a[6]) : FlashEncoder.NewSession();
    var enc = new FlashEncoder(payload, kind, a[5], session);
    using var w = new StreamWriter(a[2]);
    for (int i = 0; i < n; i++) w.WriteLine(enc.Next());
    Console.WriteLine($"C# encoded {n} frames, K={enc.ChunkCount}, raw={payload.Length}");
    return 0;
}

static int Decode(string[] a)
{
    var dec = new FlashDecoder();
    int lines = 0;
    foreach (var line in File.ReadLines(a[1])) { lines++; dec.Ingest(line); if (dec.IsComplete) break; }
    if (!dec.IsComplete) return Fail($"C# decoder incomplete after {lines} frames ({dec.SolvedCount}/{dec.ChunkCount})");
    var bytes = dec.Finish();
    if (bytes == null) return Fail("C# decoder: CRC or inflate failed");
    File.WriteAllBytes(a[2], bytes);
    Console.WriteLine($"C# decoded {bytes.Length} bytes after {lines} frames, label=\"{dec.Label}\"");
    return 0;
}

// ---------------------------------------------------------------------------
static JsonObject Obj(string path) =>
    File.Exists(path) ? (JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject()) : new JsonObject();

static int CsBuild(string[] a)
{
    var cs = FlashChangeSet.BuildChangeSet(Obj(a[1]), Obj(a[2]), Obj(a[3]), Obj(a[4]), "Windows",
                                           new DateTime(2026, 9, 27, 12, 0, 0));
    File.WriteAllText(a[5], cs?.ToJsonString() ?? "{}");
    Console.WriteLine($"C# built change set: {(cs == null ? "no changes" : FlashChangeSet.Summarize(cs))}");
    return 0;
}

static int CsApply(string[] a)
{
    var data = Obj(a[1]); var settings = Obj(a[2]); var cs = Obj(a[3]);
    FlashChangeSet.ApplyChangeSet(cs, data, settings, new DateTime(2026, 9, 27, 12, 0, 0));
    File.WriteAllText(a[4], data.ToJsonString());
    File.WriteAllText(a[5], settings.ToJsonString());
    Console.WriteLine("C# applied change set");
    return 0;
}

static int SnapBuild(string[] a)
{
    File.WriteAllText(a[3], FlashChangeSet.BuildSnapshot(Obj(a[1]), Obj(a[2])).ToJsonString());
    Console.WriteLine("C# built snapshot");
    return 0;
}

static int SnapApply(string[] a)
{
    var settings = Obj(a[3]);
    var data = FlashChangeSet.ApplySnapshot(Obj(a[1]), settings, new DateTime(2026, 9, 27, 12, 0, 0),
                                            out var had, existingData: Obj(a[2]));
    File.WriteAllText(a[4], data.ToJsonString());
    File.WriteAllText(a[5], settings.ToJsonString());
    Console.WriteLine($"C# applied snapshot (carried settings: {had})");
    return 0;
}
