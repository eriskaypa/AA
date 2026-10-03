// Family (c) bundles — writer cases B01–B08, reader fixtures R01–R17, import matrix M, peek matrix P, truth tables T,
// ApplySyncedData C01 (spec 01 GF.5.c, DATA-317). Local attachment states: L0 = empty files/; L1 = files/{a.pdf
// (10 B "0123456789"), b.pdf (5 B "abcde")}. Unless stated, data.json in the data folder = A02 bytes and AppIdentity =
// Vessel-Alpha.
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class FamilyC
{
    private const string F = "bundles";

    // ---- shared setup ---------------------------------------------------------------------------------------------

    private static string A02() => DataStore.SerializeForSave(KitchenSink.Build());

    private static void LocalData(string? json = null)
    {
        File.WriteAllText(DataStore.DefaultDataFile, json ?? A02(), Utf8NoBom);
        DataStore.SetAppIdentity("Vessel-Alpha");
    }

    private static void LocalState(string state)
    {
        Directory.CreateDirectory(DataStore.FilesFolder);
        foreach (var f in Directory.GetFiles(DataStore.FilesFolder)) File.Delete(f);
        if (state == "L1")
        {
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "a.pdf"), "0123456789");
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "b.pdf"), "abcde");
        }
    }

    /// <summary>A scratch folder outside the data folder for export destinations and extracted inputs.</summary>
    private static string Scratch(CaseRun r)
    {
        var d = r.DataDir.TrimEnd('/', '\\') + "-scratch";
        Directory.CreateDirectory(d);
        r.Mask.Literal(d, "%%TEMP%%");
        return d;
    }

    private static JsonArray FilesListing()
    {
        var list = new JsonArray();
        if (!Directory.Exists(DataStore.FilesFolder)) return list;
        foreach (var f in Directory.GetFiles(DataStore.FilesFolder).OrderBy(x => Path.GetFileName(x), StringComparer.Ordinal))
            list.Add(new JsonObject { ["name"] = Path.GetFileName(f), ["size"] = new FileInfo(f).Length });
        return list;
    }

    /// <summary>B and R bundles (file names of the committed archives) — the M and P matrices run over all of them.</summary>
    private static readonly string[] MatrixBundles =
    {
        "B01.bundle.zip", "B02.bundle.zip", "B03.bundle.zip", "B04.bundle.zip", "B05a.bundle.zip",
        "R01.bundle.zip", "R02.bundle.zip", "R03.bundle.zip", "R04.bundle.zip", "R05.bundle.zip", "R06.bundle.zip",
        "R07.bundle.zip", "R08.bundle.zip", "R09.bundle.zip", "R10.bundle.zip", "R11.bundle.zip", "R12.bundle.zip",
        "R13.bundle.zip", "R14.bundle.zip", "R15.bundle.zip", "R16.bundle.aaz", "R17a.bundle.zip", "R17b.bundle.zip",
    };

    /// <summary>W21 (GF.6.8): the Explorer "Send to → Compressed (zipped) folder" bundle, made by hand on Windows and
    /// committed as windows/bundles/R20.explorer.bundle.zip. The M and P matrices gain its rows on the first generate
    /// after it is committed (CaseDef.RequiresFile); until then they are skipped.</summary>
    internal const string ExplorerBundle = "R20.explorer.bundle.zip";
    private const string ExplorerBundleRel = "windows/bundles/" + ExplorerBundle;

    /// <summary>The fixture-root-relative path of a matrix bundle (recorded as the cell's `bundle` input).</summary>
    private static string BundleRel(string bundle) => bundle == ExplorerBundle ? ExplorerBundleRel : "bundles/" + bundle;

    private static bool PlatformSensitive(string bundle) =>
        bundle.StartsWith("R14", StringComparison.Ordinal) || bundle.StartsWith("R15", StringComparison.Ordinal) ||
        bundle.StartsWith("R17", StringComparison.Ordinal);

    public static IEnumerable<CaseDef> Cases()
    {
        // ---- writer cases B01–B08 ---------------------------------------------------------------------------------
        yield return Writer("B01", "files/ with a NFC non-ASCII name, an empty file and a sub-folder; TextOnlyExport off", r =>
        {
            LocalData();
            Directory.CreateDirectory(Path.Combine(DataStore.FilesFolder, "sub"));
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "0123456789abcdef0123456789abcdef_Manual v2.pdf"), "0123456789");
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "fedcba9876543210fedcba9876543210_W\u00E4rtsil\u00E4 manual.pdf".Normalize(NormalizationForm.FormC)), "abcde");
            File.WriteAllBytes(Path.Combine(DataStore.FilesFolder, "empty.txt"), Array.Empty<byte>());
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "sub", "x.txt"), "xyz");
            Export(r, null);
        });
        yield return Writer("B02", "same as B01 with SetTextOnlyExport(true)", r =>
        {
            LocalData();
            File.WriteAllText(Path.Combine(DataStore.FilesFolder, "0123456789abcdef0123456789abcdef_Manual v2.pdf"), "0123456789");
            DataStore.SetTextOnlyExport(true);
            Export(r, null);
        });
        yield return Writer("B03", "empty files/ → a directory entry", r => { LocalData(); Directory.CreateDirectory(DataStore.FilesFolder); Export(r, null); });
        yield return Writer("B04", "active data file outside the data folder (A01 + a stamp)", r =>
        {
            LocalData();
            var ext = Scratch(r);
            var path = Path.Combine(ext, "aa-data.json");
            var a01 = new AppData { LastModified = D_LM };
            File.WriteAllText(path, DataStore.SerializeForSave(a01), Utf8NoBom);
            DataStore.SetCurrentDataFile(path);
            Export(r, null);
        });
        yield return Writer("B05a", "active file missing, default present → fallback content, no LastModified", r =>
        {
            LocalData();
            DataStore.SetCurrentDataFile(Path.Combine(Scratch(r), "missing.json"));
            Export(r, null);
        });
        yield return Writer("B05b", "active and default both missing → no data.json entry", r =>
        {
            DataStore.SetAppIdentity("Vessel-Alpha");
            DataStore.SetCurrentDataFile(Path.Combine(Scratch(r), "missing.json"));
            Export(r, null);
        });
        yield return new CaseDef
        {
            Id = "B06a", Family = F, Compare = "json-semantic", Title = "destination inside the data folder → IOException",
            Settles = new[] { "01 §7.7", "01 D-13" },
            Run = r => { LocalData(); ExportError(r, Path.Combine(DataStore.AppFolder, "x.zip")); },
        };
        yield return new CaseDef
        {
            Id = "B06b", Family = F, Compare = "json-semantic", Title = "sibling folder <datadir>2 → IOException (prefix-match defect D-13)",
            Settles = new[] { "01 D-13" },
            Run = r =>
            {
                LocalData();
                var sibling = DataStore.AppFolder.TrimEnd('/', '\\') + "2";
                Directory.CreateDirectory(sibling);
                try { ExportError(r, Path.Combine(sibling, "x.zip")); }
                finally { Directory.Delete(sibling, true); }
                r.DivergentRecordOnly("01 D-13 fixed on the Mac (P2): a sibling folder sharing the prefix is a valid destination");
            },
        };
        yield return new CaseDef
        {
            Id = "B07", Family = F, Title = "BundleSource → Serialize(Opts) (the 01 §4.4 literal)",
            Settles = new[] { "01 §4.4" },
            Run = r =>
            {
                var s = new BundleSource
                {
                    Identity = "Vessel-Alpha", Machine = "BRIDGE-PC",
                    WrittenUtc = new DateTime(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc).AddTicks(1234567),
                    LastModified = D_LM, DataOnly = false,
                };
                r.Text("result", "source", "json", JsonSerializer.Serialize(s, Opts));
            },
        };
        var b08 = new (string Title, BundleSource Source)[]
        {
            ("LastModified null", new BundleSource { Identity = "Vessel-Alpha", Machine = "BRIDGE-PC", WrittenUtc = D_Z, LastModified = null }),
            ("Identity \"\"", new BundleSource { Identity = "", Machine = "BRIDGE-PC", WrittenUtc = D_Z, LastModified = D_LM }),
            ("WrittenUtc default", new BundleSource { Identity = "Vessel-Alpha", Machine = "BRIDGE-PC", LastModified = D_LM, DataOnly = true }),
        };
        for (int i = 0; i < b08.Length; i++)
        {
            var (title, src) = b08[i];
            yield return new CaseDef
            {
                Id = $"B08.{i + 1}", Family = F, Title = "BundleSource variant: " + title,
                Settles = new[] { "01 §4.4" },
                Run = r =>
                {
                    r.Text("result", "source", "json", JsonSerializer.Serialize(src, Opts));
                    r.Json("display", "display", new JsonObject { ["WrittenLocal"] = src.WrittenLocal }, mac: src.WrittenUtc == default);
                },
            };
        }

        // ---- reader fixtures R01–R17 ----------------------------------------------------------------------------------
        var a01 = DataStore.SerializeForSave(new AppData());
        var readers = new (string Id, string Title, Action<ZipArchive> Fill, bool Descriptor)[]
        {
            ("R01", "data.json (A01) only", z => Add(z, "data.json", a01), false),
            ("R02", "data.json, source.json {DataOnly:true}, files/a.pdf", z => { Add(z, "data.json", a01); Add(z, "source.json", Source(true)); Add(z, "files/a.pdf", "0123456789"); }, false),
            ("R03", "data.json, source.json {DataOnly:false}, directory entry files/ only", z => { Add(z, "data.json", a01); Add(z, "source.json", Source(false)); z.CreateEntry("files/"); }, false),
            ("R04", "data.json, files/a.pdf (10 B), files/b.pdf (5 B), no source.json", z => { Add(z, "data.json", a01); Add(z, "files/a.pdf", "0123456789"); Add(z, "files/b.pdf", "abcde"); }, false),
            ("R05", "as R04 with files/A.PDF", z => { Add(z, "data.json", a01); Add(z, "files/A.PDF", "0123456789"); Add(z, "files/b.pdf", "abcde"); }, false),
            ("R06", "as R04 with a.pdf 11 B", z => { Add(z, "data.json", a01); Add(z, "files/a.pdf", "0123456789X"); Add(z, "files/b.pdf", "abcde"); }, false),
            ("R07", "data.json, files/a.pdf (10 B)", z => { Add(z, "data.json", a01); Add(z, "files/a.pdf", "0123456789"); }, false),
            ("R08", "AA/data.json only (nested)", z => Add(z, "AA/data.json", a01), false),
            ("R09", "data.json, ../evil.txt", z => { Add(z, "data.json", a01); Add(z, "../evil.txt", "evil"); }, false),
            ("R10", "R04 through a non-seekable stream (data descriptors), files/b.pdf Stored", z =>
            {
                Add(z, "data.json", a01); Add(z, "files/a.pdf", "0123456789");
                Add(z, "files/b.pdf", "abcde", CompressionLevel.NoCompression);
            }, true),
            ("R11", "data.json and source.json each with a UTF-8 BOM", z =>
            {
                AddBytes(z, "data.json", new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Utf8(a01)).ToArray());
                AddBytes(z, "source.json", new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Utf8(Source(false))).ToArray());
            }, false),
            ("R12", "data.json = {\"Tasks\":[ (invalid) + files/c.pdf", z => { Add(z, "data.json", "{\"Tasks\":["); Add(z, "files/c.pdf", "ccc"); }, false),
            ("R13", "source.json = {bad + data.json + files/a.pdf", z => { Add(z, "data.json", a01); Add(z, "source.json", "{bad"); Add(z, "files/a.pdf", "0123456789"); }, false),
            ("R14", "DATA.JSON (upper case) only", z => Add(z, "DATA.JSON", a01), false),
            ("R15", "data.json + an absolute entry /etc/evil + a backslash entry files\\a.pdf", z =>
            {
                Add(z, "data.json", a01); Add(z, "/etc/evil", "evil"); Add(z, "files\\a.pdf", "0123456789");
            }, false),
            ("R16", "iOS-shaped data-only bundle (SchemaVersion 3, unknown key, iOS source.json)", z =>
            {
                Add(z, "data.json", "{\"Tasks\":[],\"FromIOS\":{\"v\":1},\"SchemaVersion\":3}");
                Add(z, "source.json", "{\"Identity\":\"iPhone\",\"Machine\":\"iPhone\",\"WrittenUtc\":\"2026-09-29T08:15:30Z\",\"DataOnly\":true,\"App\":\"AA iOS\",\"Build\":\"42\"}");
            }, false),
        };
        foreach (var (id, title, fill, descriptor) in readers)
        {
            var file = id == "R16" ? "R16.bundle.aaz" : $"{id}.bundle.zip";
            yield return new CaseDef
            {
                Id = id, Family = F, Normative = "record-only", Title = "reader fixture: " + title,
                Settles = new[] { "01 §7.7" },
                Run = r =>
                {
                    var bytes = BuildZip(fill, descriptor, null);
                    r.Side(file, bytes, mask: false);
                    if (id == "R16") r.Input("iosName", "AA-backup-iOS-dataonly-20260929-1015.aaz");
                    ZipInspect.WriteManifest(r, "bundle", bytes, orderSignificant: false, writePayloads: false);
                },
            };
        }
        yield return new CaseDef
        {
            Id = "R17", Family = F, Normative = "record-only", Title = "files/Wärtsilä.pdf stored with a UTF-8 name (bit 11) and as CP437 bytes",
            Settles = new[] { "01 §6.7" },
            Run = r =>
            {
                var utf8 = BuildZip(z => { Add(z, "data.json", a01); Add(z, "files/W\u00E4rtsil\u00E4.pdf", "abcde"); }, false, null);
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                var cp437 = BuildZip(z => { Add(z, "data.json", a01); Add(z, "files/W\u00E4rtsil\u00E4.pdf", "abcde"); }, false, Encoding.GetEncoding(437));
                r.Side("R17a.bundle.zip", utf8, mask: false);
                r.Side("R17b.bundle.zip", cp437, mask: false);
                ZipInspect.WriteManifest(r, "bundle", utf8, orderSignificant: false, writePayloads: false);
            },
        };

        // ---- import matrix M (one process per cell) -----------------------------------------------------------------
        foreach (var bundle in MatrixBundles)
            foreach (var op in new[] { "smart", "shared" })
                foreach (var state in new[] { "L0", "L1" })
                {
                    var stem = bundle.Split('.')[0];
                    var sensitive = PlatformSensitive(bundle);
                    yield return new CaseDef
                    {
                        Id = $"M.{stem}.{op}.{state}", Family = F, OwnProcess = true, Compare = "json-semantic",
                        Runs = sensitive ? Runs.Both : Runs.Any, Normative = sensitive ? "record-only" : "must",
                        NormativeWindows = sensitive ? "record-only" : null,
                        Title = $"{(op == "smart" ? "ImportBundleSmart" : "ImportSharedBundle")}({bundle}) with local {state}",
                        Settles = new[] { "01 §7.7", "01 D-3" },
                        Run = r => MatrixCell(r, bundle, op, state),
                    };
                }

        // W21: the Explorer ZIP. Its entry names are encoded by the Windows shell (OEM code page or UTF-8, depending on
        // the build) and it carries no source.json, so the unix run is a record (the Mac's own CP437 rule is 01 §6.7)
        // and the windows run — AA.exe on its own platform's archive — is the reference the Mac should meet.
        foreach (var op in new[] { "smart", "shared" })
            foreach (var state in new[] { "L0", "L1" })
                yield return new CaseDef
                {
                    Id = $"M.R20.{op}.{state}", Family = F, OwnProcess = true, Compare = "json-semantic",
                    Runs = Runs.Both, Normative = "record-only", NormativeWindows = "should", RequiresFile = ExplorerBundleRel,
                    Title = $"{(op == "smart" ? "ImportBundleSmart" : "ImportSharedBundle")}(W21 Explorer ZIP) with local {state}",
                    Settles = new[] { "01 §7.7", "01 §6.7", "GF.6.8 W21" },
                    Run = r => MatrixCell(r, ExplorerBundle, op, state),
                };

        // ---- peek matrix P ------------------------------------------------------------------------------------------
        foreach (var bundle in MatrixBundles)
        {
            var stem = bundle.Split('.')[0];
            yield return new CaseDef
            {
                Id = $"P.{stem}", Family = F, Compare = "json-semantic", Title = $"peeks of {bundle}",
                Normative = PlatformSensitive(bundle) ? "record-only" : "must",
                Settles = new[] { "01 §3.9", "01 §3.10" },
                Run = r => PeekCell(r, bundle),
            };
        }
        yield return new CaseDef
        {
            Id = "P.R20", Family = F, Compare = "json-semantic", Title = "peeks of the W21 Explorer ZIP",
            Runs = Runs.Both, Normative = "record-only", NormativeWindows = "should", RequiresFile = ExplorerBundleRel,
            Settles = new[] { "01 §3.9", "01 §3.10", "GF.6.8 W21" },
            Run = r => PeekCell(r, ExplorerBundle),
        };

        // ---- truth tables T -------------------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "T", Family = F, Compare = "json-semantic",
            Title = "IsDataOnlyBundle and AttachmentsMatch truth tables (private, by reflection)",
            Settles = new[] { "01 §3.10", "01 §7.7" },
            Run = r => TruthTables(r),
        };

        // ---- C01 ApplySyncedData --------------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "C01", Family = F, Runs = Runs.Both, Normative = "record-only", NormativeWindows = "must",
            Title = "ApplySyncedData(A02 + three foreign attachment paths) → model, data file, settings",
            Settles = new[] { "01 DATA-049", "01 §3.7" },
            Run = r =>
            {
                Directory.CreateDirectory(DataStore.FilesFolder);
                File.WriteAllText(Path.Combine(DataStore.FilesFolder, "ab12_x.pdf"), "0123456789");
                var ks = KitchenSink.Build();
                var c = ks.Equipment[0].Container;
                c.Files.Add(new FileItem { Id = G(208), Name = "win.pdf", Path = @"C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf", Added = D_L });
                c.Files.Add(new FileItem { Id = G(209), Name = "mac.pdf", Path = "/Users/bob/AA/files/ab12_x.pdf", Added = D_L });
                c.Files.Add(new FileItem { Id = G(210), Name = "unc.pdf", Path = @"\\srv\share\x.pdf", LinkInPlace = true, Added = D_L });
                var json = JsonSerializer.Serialize(ks, Opts);
                r.InputFile($"{r.Id}.input.json", json);
                var returned = DataStore.ApplySyncedData(json);
                r.Text("model", "model", "json", JsonSerializer.Serialize(returned, Opts));
                r.Text("data", "datafile", "json", File.ReadAllText(DataStore.DefaultDataFile));
                r.Text("settings", "settings", "json", File.ReadAllText(DataStore.SettingsFile), mac: false);
            },
        };
    }

    // ---- writer helpers -------------------------------------------------------------------------------------------------

    private static CaseDef Writer(string id, string title, Action<CaseRun> run) => new()
    {
        Id = id, Family = F, Compare = "zip-manifest", Title = "ExportFolderToZip: " + title,
        Settles = new[] { "01 §4.4", "01 §4.5", "01 §7.7" },
        Run = run,
    };

    /// <summary>Exports, records the archive, its manifest + payloads, and masks the source stamp.</summary>
    private static void Export(CaseRun r, bool? includeAttachments)
    {
        var dest = Path.Combine(Scratch(r), r.Id + ".bundle.zip");
        if (includeAttachments is bool inc) DataStore.ExportFolderToZip(dest, inc);
        else DataStore.ExportFolderToZip(dest);
        var bytes = File.ReadAllBytes(dest);
        // source.json: WrittenUtc → %%NOWUTC%% (Machine is masked as a quoted literal by every case).
        using (var z = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read))
        {
            var se = z.GetEntry("source.json");
            if (se != null)
            {
                using var s = new StreamReader(se.Open());
                var src = JsonSerializer.Deserialize<BundleSource>(s.ReadToEnd(), Opts);
                if (src != null && src.WrittenUtc != default) r.Mask.Now(src.WrittenUtc);
            }
        }
        r.Side(r.Id + ".bundle.zip", bytes, mask: false);
        r.Input("textOnlyExport", DataStore.TextOnlyExport);
        r.Input("appIdentity", DataStore.AppIdentity);
        ZipInspect.WriteManifest(r, "bundle", bytes, orderSignificant: false);
    }

    private static void ExportError(CaseRun r, string dest)
    {
        r.Input("destination", dest);
        try
        {
            DataStore.ExportFolderToZip(dest);
            r.Json("result", "outcome", new JsonObject { ["threw"] = false });
        }
        catch (Exception ex)
        {
            r.Json("result", "outcome", Shapes.ExceptionShape(ex, aaAuthored: ex is IOException && ex.Message.StartsWith("Choose a destination", StringComparison.Ordinal)));
        }
    }

    // ---- reader fixture helpers ----------------------------------------------------------------------------------------

    private static string Source(bool dataOnly) =>
        JsonSerializer.Serialize(new BundleSource { Identity = "Vessel-Alpha", Machine = "BRIDGE-PC", WrittenUtc = D_Z, LastModified = D_LM, DataOnly = dataOnly }, Opts);

    private static void Add(ZipArchive z, string name, string text, CompressionLevel level = CompressionLevel.Optimal) =>
        AddBytes(z, name, Utf8(text), level);

    private static void AddBytes(ZipArchive z, string name, byte[] bytes, CompressionLevel level = CompressionLevel.Optimal)
    {
        var e = z.CreateEntry(name, level);
        // Fixed timestamps so regeneration is byte-identical (DATA-303).
        e.LastWriteTime = new DateTimeOffset(2026, 9, 29, 11, 15, 30, TimeSpan.Zero);
        using var s = e.Open();
        s.Write(bytes, 0, bytes.Length);
    }

    /// <summary>Builds an archive; with <paramref name="descriptor"/> through a non-seekable stream (bit 3 data
    /// descriptors).</summary>
    private static byte[] BuildZip(Action<ZipArchive> fill, bool descriptor, Encoding? names)
    {
        var ms = new MemoryStream();
        Stream target = descriptor ? new NonSeekable(ms) : ms;
        using (var z = new ZipArchive(target, ZipArchiveMode.Create, leaveOpen: true, entryNameEncoding: names))
            fill(z);
        return ms.ToArray();
    }

    private sealed class NonSeekable(Stream inner) : Stream
    {
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => inner.Flush();
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => inner.Write(buffer, offset, count);
    }

    // ---- matrices --------------------------------------------------------------------------------------------------

    /// <summary>The committed archive of an earlier group, copied to the scratch folder (imports never read from the
    /// fixture tree in place).</summary>
    private static string StagedBundle(CaseRun r, string bundle)
    {
        // This run's own archive first (the windows run writes `any` cases under <neutral>/windows/bundles), then the
        // committed unix archive the staging tree was seeded with (bundles/).
        var candidates = bundle == ExplorerBundle
            ? new[] { Path.Combine(r.Root, ExplorerBundleRel.Replace('/', Path.DirectorySeparatorChar)) }   // committed by hand (W21)
            : new[]
            {
                Path.Combine(r.Root, r.Rel(bundle).Replace('/', Path.DirectorySeparatorChar)),
                Path.Combine(r.Root, "bundles", bundle),
            };
        var src = candidates.FirstOrDefault(File.Exists)
                  ?? throw new FileNotFoundException("bundle archive not generated yet", candidates[0]);
        var dst = Path.Combine(Scratch(r), bundle);
        File.Copy(src, dst, true);
        return dst;
    }

    private static void PeekCell(CaseRun r, string bundle)
    {
        var path = StagedBundle(r, bundle);
        var src = DataStore.PeekBundleSource(path);
        var data = DataStore.PeekZipData(path);
        r.Input("bundle", BundleRel(bundle));
        r.Json("result", "peek", new JsonObject
        {
            ["lastModified"] = Shapes.DateOrNull(DataStore.PeekZipLastModified(path)),
            ["source"] = src == null ? null : JsonNode.Parse(JsonSerializer.Serialize(src, Opts)),
            ["identity"] = DataStore.PeekBundleIdentity(path),
            ["data"] = data == null ? null : JsonNode.Parse(JsonSerializer.Serialize(data, Opts)),
        });
    }

    private static void MatrixCell(CaseRun r, string bundle, string op, string state)
    {
        LocalData();
        LocalState(state);
        var path = StagedBundle(r, bundle);
        r.Input("bundle", BundleRel(bundle));
        r.Input("operation", op == "smart" ? "ImportBundleSmart" : "ImportSharedBundle");
        r.Input("localState", state);
        var before = File.ReadAllBytes(DataStore.DefaultDataFile);
        var filesBefore = FilesListing().ToJsonString();
        string? result = null;
        JsonObject? exception = null;
        try
        {
            if (op == "smart") result = DataStore.ImportBundleSmart(path).ToString();
            else DataStore.ImportSharedBundle(path);
        }
        catch (Exception ex)
        {
            var aa = ex is InvalidDataException && ex.Message.Contains("has no data.json", StringComparison.Ordinal);
            exception = (JsonObject)Shapes.ExceptionShape(ex, aa)["exception"]!.DeepClone();
        }
        var after = File.Exists(DataStore.DefaultDataFile) ? File.ReadAllBytes(DataStore.DefaultDataFile) : Array.Empty<byte>();
        var changed = !before.AsSpan().SequenceEqual(after);
        var cell = new JsonObject
        {
            ["result"] = op == "smart" ? result : (exception == null ? "Applied" : null),
            ["threw"] = exception != null,
            ["exception"] = exception,
            ["filesAfter"] = FilesListing(),
            ["dataJsonChanged"] = changed,
            ["currentDataFileIsDefault"] = string.Equals(DataStore.CurrentDataFile, DataStore.DefaultDataFile, StringComparison.Ordinal),
            ["localModifiedBeforeThrow"] = exception != null && (changed || FilesListing().ToJsonString() != filesBefore),
        };
        r.Json("cell", "cell", cell);
        if (changed && after.Length > 0)
        {
            var text = Utf8NoBom.GetString(after);
            r.Mask.AutoMask(text, Utf8NoBom.GetString(before));
            r.Text("data", "datafile", "json", text);
        }
    }

    private static void TruthTables(CaseRun r)
    {
        var scratch = Scratch(r);
        var dataOnly = new JsonArray();
        var rows = new (string Name, string? Source, bool FilesDir, int FileCount)[]
        {
            ("source DataOnly true, files/ present", "{\"DataOnly\":true}", true, 1),
            ("no source, no files/", null, false, 0),
            ("source DataOnly false, no files/", "{\"DataOnly\":false}", false, 0),
            ("no source, empty files/", null, true, 0),
            ("DataOnly false, files/ with 1", "{\"DataOnly\":false}", true, 1),
            ("source.json invalid JSON, files/ present", "{bad", true, 1),
            ("source.json = null literal, files/ present", "null", true, 1),
            ("DataOnly:\"true\" (string), files/ present", "{\"DataOnly\":\"true\"}", true, 1),
        };
        foreach (var (name, source, filesDir, count) in rows)
        {
            var stage = Path.Combine(scratch, "stage-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage);
            if (source != null) File.WriteAllText(Path.Combine(stage, "source.json"), source);
            var files = Path.Combine(stage, "files");
            if (filesDir)
            {
                Directory.CreateDirectory(files);
                for (int i = 0; i < count; i++) File.WriteAllText(Path.Combine(files, $"f{i}.pdf"), "x");
            }
            dataOnly.Add(new JsonObject { ["row"] = name, ["result"] = Call<bool>(typeof(DataStore), "IsDataOnlyBundle", stage, files) });
            Directory.Delete(stage, true);
        }
        var match = new JsonArray();
        var mrows = new (string Name, (string, int)[]? Bundle, (string, int)[]? Local, bool Sub)[]
        {
            ("equal sets", new[] { ("a.pdf", 10), ("b.pdf", 5) }, new[] { ("a.pdf", 10), ("b.pdf", 5) }, false),
            ("case-only difference A.PDF/a.pdf", new[] { ("A.PDF", 10), ("b.pdf", 5) }, new[] { ("a.pdf", 10), ("b.pdf", 5) }, false),
            ("case-only difference Straße.pdf/STRASSE.pdf", new[] { ("Straße.pdf", 3) }, new[] { ("STRASSE.pdf", 3) }, false),
            ("size difference", new[] { ("a.pdf", 11) }, new[] { ("a.pdf", 10) }, false),
            ("extra local file", new[] { ("a.pdf", 10) }, new[] { ("a.pdf", 10), ("b.pdf", 5) }, false),
            ("extra bundle file", new[] { ("a.pdf", 10), ("b.pdf", 5) }, new[] { ("a.pdf", 10) }, false),
            ("missing bundle directory", null, new[] { ("a.pdf", 10) }, false),
            ("missing local directory", new[] { ("a.pdf", 10) }, null, false),
            ("files in sub-folders (ignored)", new[] { ("a.pdf", 10) }, new[] { ("a.pdf", 10) }, true),
        };
        foreach (var (name, bundleFiles, localFiles, sub) in mrows)
        {
            var root = Path.Combine(scratch, "match-" + Guid.NewGuid().ToString("N"));
            var b = Path.Combine(root, "bundle"); var l = Path.Combine(root, "local");
            void Fill(string dir, (string, int)[]? set)
            {
                if (set == null) return;
                Directory.CreateDirectory(dir);
                foreach (var (n, size) in set) File.WriteAllBytes(Path.Combine(dir, n), Enumerable.Repeat((byte)'x', size).ToArray());
                if (sub) { Directory.CreateDirectory(Path.Combine(dir, "sub")); File.WriteAllText(Path.Combine(dir, "sub", Guid.NewGuid().ToString("N")), "s"); }
            }
            Fill(b, bundleFiles); Fill(l, localFiles);
            bool result;
            try { result = Call<bool>(typeof(DataStore), "AttachmentsMatch", b, l); }
            catch (Exception) { result = false; }
            match.Add(new JsonObject { ["row"] = name, ["result"] = result });
            Directory.Delete(root, true);
        }
        r.Json("result", "tables", new JsonObject { ["isDataOnlyBundle"] = dataOnly, ["attachmentsMatch"] = match }, mac: false);
    }
}
