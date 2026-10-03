// Family (d) crypto — cases K01–K10 (spec 01 GF.5.d, DATA-318): PBKDF2 vectors, the app password, `enc:` blobs from
// the generator's own reference implementation of 01 §4.7 validated by the REAL PasswordService.Decrypt, random-IV
// blobs with IV-extraction equivalence, negatives, BOM sniffing, IsEncrypted, and the per-item lock.
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class FamilyD
{
    private const string F = "crypto";
    private const int Iterations = 100_000;

    /// <summary>S = bytes 00 01 … 0F.</summary>
    public static readonly byte[] S = Enumerable.Range(0, 16).Select(i => (byte)i).ToArray();
    /// <summary>S2 = the first 16 bytes of SHA-256("AA-fixture-salt").</summary>
    public static readonly byte[] S2 = SHA256.HashData(Utf8("AA-fixture-salt")).Take(16).ToArray();
    /// <summary>IV = bytes 10 11 … 1F.</summary>
    public static readonly byte[] IV = Enumerable.Range(0x10, 16).Select(i => (byte)i).ToArray();
    public static readonly byte[] Bom = { 0xEF, 0xBB, 0xBF };

    public const string Spec0576Xaml =
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Secret</Run></Paragraph></Section>";

    private static string Hex(byte[] b) => Convert.ToHexString(b).ToLowerInvariant();
    private static string HashB64(string pw, byte[] salt) =>
        Convert.ToBase64String(Rfc2898DeriveBytes.Pbkdf2(pw, salt, Iterations, HashAlgorithmName.SHA256, 32));

    /// <summary>The generator's own implementation of 01 §4.7 on .NET primitives (fixed IV).</summary>
    public static string RefEncrypt(string pw, byte[] salt, byte[] iv, byte[] plaintext)
    {
        var k = Rfc2898DeriveBytes.Pbkdf2(pw, salt, Iterations, HashAlgorithmName.SHA256, 64);
        using var aes = Aes.Create();
        aes.Key = k[..32];
        var ct = aes.EncryptCbc(plaintext, iv, PaddingMode.PKCS7);
        var mac = HMACSHA256.HashData(k[32..], iv.Concat(ct).ToArray());
        return "enc:" + Convert.ToBase64String(iv.Concat(ct).Concat(mac).ToArray());
    }

    /// <summary>The real app decrypt: LoadFrom(hash, salt) + Unlock(pw) + Decrypt(blob).</summary>
    private static string? RealDecrypt(string pw, byte[] salt, string blob)
    {
        PasswordService.LoadFrom(HashB64(pw, salt), Convert.ToBase64String(salt));
        if (!PasswordService.Unlock(pw)) return "<unlock failed>";
        return PasswordService.Decrypt(blob);
    }

    public static IEnumerable<CaseDef> Cases()
    {
        yield return new CaseDef
        {
            Id = "K01", Family = F, Compare = "json-semantic", Title = "PBKDF2-HMAC-SHA256 derivations (dkLen 32/64, salts S/S2) + primitive",
            Settles = new[] { "01 §7.1", "01 §4.7" },
            Run = r =>
            {
                var passwords = new[]
                {
                    "correct horse", "redemption", "pässwörd", "pässwörd", "test1234", "", "😀 emoji",
                    new string('a', 1000), "  padded  ",
                };
                var rows = new JsonArray();
                foreach (var pw in passwords)
                    foreach (var (saltName, salt) in new[] { ("S", S), ("S2", S2) })
                    {
                        var k32 = Rfc2898DeriveBytes.Pbkdf2(pw, salt, Iterations, HashAlgorithmName.SHA256, 32);
                        var k64 = Rfc2898DeriveBytes.Pbkdf2(pw, salt, Iterations, HashAlgorithmName.SHA256, 64);
                        // The app's own split (private DeriveKeys), proving the keys are K[0..32) / K[32..64).
                        var keys = Call<(byte[] Enc, byte[] Mac)>(typeof(PasswordService), "DeriveKeys", pw, salt);
                        rows.Add(new JsonObject
                        {
                            ["password"] = pw, ["passwordUtf8Hex"] = Hex(Utf8(pw)), ["salt"] = saltName, ["saltHex"] = Hex(salt),
                            ["iterations"] = Iterations,
                            ["dk32Hex"] = Hex(k32), ["dk32Base64"] = Convert.ToBase64String(k32),
                            ["dk64Hex"] = Hex(k64), ["dk64Base64"] = Convert.ToBase64String(k64),
                            ["prefixEqual"] = k64.AsSpan(0, 32).SequenceEqual(k32),
                            ["encKeyHex"] = Hex(keys.Enc), ["macKeyHex"] = Hex(keys.Mac),
                        });
                    }
                var prim = Rfc2898DeriveBytes.Pbkdf2(Utf8("password"), Utf8("salt"), 1, HashAlgorithmName.SHA256, 32);
                r.Input("passwords", new JsonArray(passwords.Select(p => (JsonNode?)p).ToArray()));
                r.Json("result", "pbkdf2", new JsonObject
                {
                    ["rows"] = rows,
                    ["primitive"] = new JsonObject { ["password"] = "password", ["salt"] = "salt", ["iterations"] = 1, ["dkLen"] = 32, ["hex"] = Hex(prim) },
                    ["nfcEqualsNfd"] = Hex(Rfc2898DeriveBytes.Pbkdf2(passwords[2], S, Iterations, HashAlgorithmName.SHA256, 32))
                                       == Hex(Rfc2898DeriveBytes.Pbkdf2(passwords[3], S, Iterations, HashAlgorithmName.SHA256, 32)),
                });
            },
        };

        yield return new CaseDef
        {
            Id = "K02", Family = F, Compare = "json-semantic", Title = "PasswordService states × Verify/Unlock",
            Settles = new[] { "01 §7.1", "01 DATA-084" },
            Run = r =>
            {
                var hash = HashB64("correct horse", S);
                var salt = Convert.ToBase64String(S);
                var states = new (string Name, string? Hash, string? Salt)[]
                {
                    ("none", null, null), ("hash(correct horse,S), S", hash, salt), ("\"\", \"\"", "", ""),
                    ("hash, null", hash, null), ("null, S", null, salt), ("hash, \"%%%\"", hash, "%%%"),
                };
                var probes = new[] { "correct horse", "Correct horse", "correct horse ", "", "redemption", "Redemption" };
                var rows = new JsonArray();
                foreach (var (name, h, s) in states)
                {
                    var row = new JsonObject { ["state"] = name, ["hash"] = h, ["salt"] = s };
                    try
                    {
                        PasswordService.LoadFrom(h, s);
                        row["hasPassword"] = PasswordService.HasPassword;
                        var verify = new JsonObject();
                        foreach (var p in probes) verify[p] = PasswordService.Verify(p);
                        row["verify"] = verify;
                        row["unlock"] = PasswordService.Unlock("correct horse");
                        row["isUnlocked"] = PasswordService.IsUnlocked;
                    }
                    catch (Exception ex) { row["exception"] = Shapes.ExceptionShape(ex, false)["exception"]!.DeepClone(); }
                    rows.Add(row);
                }
                r.Json("result", "states", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K03", Family = F, Compare = "json-semantic",
            Title = "fixed-IV reference blobs validated by the real PasswordService.Decrypt",
            Settles = new[] { "01 §7.2", "05 §7.6", "01 §4.7" },
            Run = r =>
            {
                var plain = new (string Name, byte[] Bytes, bool Bom, string? Text, string Password)[]
                {
                    ("BOM + \"\"", Bom, true, "", "correct horse"),
                    ("BOM + <Section>hi</Section>", Bom.Concat(Utf8("<Section>hi</Section>")).ToArray(), true, "<Section>hi</Section>", "correct horse"),
                    ("\"\" without BOM", Array.Empty<byte>(), false, "", "correct horse"),
                    ("<Section>hi</Section> without BOM", Utf8("<Section>hi</Section>"), false, "<Section>hi</Section>", "correct horse"),
                    ("BOM + 12 bytes (15 total)", Bom.Concat(Utf8("123456789012")).ToArray(), true, "123456789012", "correct horse"),
                    ("BOM + 13 bytes (16 total, a full padding block)", Bom.Concat(Utf8("1234567890123")).ToArray(), true, "1234567890123", "correct horse"),
                    ("BOM + 14 bytes", Bom.Concat(Utf8("12345678901234")).ToArray(), true, "12345678901234", "correct horse"),
                    ("test1234: BOM + the 05 §7.6 XAML", Bom.Concat(Utf8(Spec0576Xaml)).ToArray(), true, Spec0576Xaml, "test1234"),
                };
                var rows = new JsonArray();
                foreach (var (name, bytes, bom, text, pw) in plain)
                {
                    var blob = RefEncrypt(pw, S, IV, bytes);
                    rows.Add(new JsonObject
                    {
                        ["name"] = name, ["password"] = pw, ["saltBase64"] = Convert.ToBase64String(S), ["ivHex"] = Hex(IV),
                        ["plaintextHex"] = Hex(bytes), ["bom"] = bom, ["text"] = text, ["blob"] = blob,
                        ["decrypted"] = RealDecrypt(pw, S, blob),
                    });
                }
                r.Json("result", "blobs", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K04", Family = F, Compare = "json-semantic", NonDeterministic = true,
            Title = "real PasswordService.Encrypt (random IV) → decrypt-only vectors + IV-extraction equivalence",
            Settles = new[] { "01 §4.7" },
            Run = r =>
            {
                var texts = new[] { "", "<Section>hi</Section>", "<Section>" + new string('x', 1000) + "😀</Section>", "123456789012345", "1234567890123456" };
                PasswordService.LoadFrom(HashB64("correct horse", S), Convert.ToBase64String(S));
                PasswordService.Unlock("correct horse");
                var rows = new JsonArray();
                foreach (var t in texts)
                {
                    var blob = PasswordService.Encrypt(t);
                    var combined = Convert.FromBase64String(blob[4..]);
                    var iv = combined[..16];
                    var re = RefEncrypt("correct horse", S, iv, Bom.Concat(Utf8(t)).ToArray());
                    rows.Add(new JsonObject
                    {
                        ["text"] = t, ["blob"] = blob, ["ivHex"] = Hex(iv), ["refEqual"] = re == blob,
                        ["decrypted"] = PasswordService.Decrypt(blob),
                    });
                }
                r.Json("result", "random-iv", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K05", Family = F, Compare = "json-semantic", Title = "Decrypt negatives on the K03 row-2 blob",
            Settles = new[] { "01 §7.2" },
            Run = r =>
            {
                var good = RefEncrypt("correct horse", S, IV, Bom.Concat(Utf8("<Section>hi</Section>")).ToArray());
                var raw = Convert.FromBase64String(good[4..]);
                string Flip(int i) { var c = (byte[])raw.Clone(); c[i] ^= 0x01; return "enc:" + Convert.ToBase64String(c); }
                var b64 = good[4..];
                var variants = new (string Name, string Blob, Func<string, string?> Decrypt)[]
                {
                    ("flip byte 0 (IV)", Flip(0), b => RealDecrypt("correct horse", S, b)),
                    ("flip byte 16 (ciphertext)", Flip(16), b => RealDecrypt("correct horse", S, b)),
                    ("flip last byte (tag)", Flip(raw.Length - 1), b => RealDecrypt("correct horse", S, b)),
                    ("truncated to 63 decoded bytes", "enc:" + Convert.ToBase64String(raw[..63]), b => RealDecrypt("correct horse", S, b)),
                    ("Base64 with embedded CRLF and spaces", "enc:" + b64[..20] + "\r\n " + b64[20..40] + "  " + b64[40..], b => RealDecrypt("correct horse", S, b)),
                    ("missing = padding", "enc:" + b64.TrimEnd('='), b => RealDecrypt("correct horse", S, b)),
                    ("URL-safe alphabet", "enc:" + b64.Replace('+', '-').Replace('/', '_'), b => RealDecrypt("correct horse", S, b)),
                    ("\"enc:\" only", "enc:", b => RealDecrypt("correct horse", S, b)),
                    ("wrong password (Correct horse)", good, b => { PasswordService.LoadFrom(HashB64("Correct horse", S), Convert.ToBase64String(S)); PasswordService.Unlock("Correct horse"); return PasswordService.Decrypt(b); }),
                    ("master password (redemption) — D-4", good, b => { PasswordService.LoadFrom(HashB64("correct horse", S), Convert.ToBase64String(S)); PasswordService.Unlock("redemption"); return PasswordService.Decrypt(b); }),
                    ("not unlocked", good, b => { PasswordService.LoadFrom(HashB64("correct horse", S), Convert.ToBase64String(S)); return PasswordService.Decrypt(b); }),
                    ("salt null", good, b => { PasswordService.LoadFrom(HashB64("correct horse", S), null); PasswordService.Unlock("redemption"); return PasswordService.Decrypt(b); }),
                };
                var rows = new JsonArray();
                foreach (var (name, blob, decrypt) in variants)
                {
                    string? result;
                    try { result = decrypt(blob); } catch (Exception ex) { result = "<threw " + ex.GetType().Name + ">"; }
                    rows.Add(new JsonObject { ["variant"] = name, ["blob"] = blob, ["result"] = result });
                }
                r.Json("result", "negatives", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K06", Family = F, Compare = "json-semantic", Title = "StreamReader BOM sniffing of decrypted plaintexts",
            Settles = new[] { "01 §4.7" },
            Run = r =>
            {
                var plains = new[]
                {
                    new byte[] { 0xFF, 0xFE, 0x41, 0x00 }, new byte[] { 0xFE, 0xFF, 0x00, 0x41 },
                    new byte[] { 0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00 },
                    new byte[] { 0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x41 }, new byte[] { 0xC3, 0x28 },
                };
                var rows = new JsonArray();
                foreach (var p in plains)
                {
                    var blob = RefEncrypt("correct horse", S, IV, p);
                    var d = RealDecrypt("correct horse", S, blob);
                    rows.Add(new JsonObject
                    {
                        ["plaintextHex"] = Hex(p), ["blob"] = blob, ["decrypted"] = d,
                        ["decryptedUtf16"] = d == null ? null : string.Join(" ", d.Select(c => ((int)c).ToString("X4"))),
                    });
                }
                r.Json("result", "bom-sniffing", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K07", Family = F, Compare = "json-semantic", Title = "IsEncrypted",
            Settles = new[] { "01 §4.7", "05 §7.6" },
            Run = r =>
            {
                var inputs = new string?[] { null, "", "enc:", "enc:x", "ENC:x", " enc:x", "enc", "<Section" };
                var rows = new JsonArray();
                foreach (var s in inputs) rows.Add(new JsonObject { ["input"] = s, ["result"] = PasswordService.IsEncrypted(s) });
                r.Json("result", "is-encrypted", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K08", Family = F, Compare = "json-semantic", Title = "ItemLockService.Verify truth table",
            Settles = new[] { "01 §7.1", "04 §7.8", "04:1018" },
            Run = r =>
            {
                var probes = new[] { "correct horse", "Correct horse", "correct horse ", "", "redemption", "Redemption" };
                var items = new (string Name, string? Hash, string? Salt, string[] Probes)[]
                {
                    ("locked (V/LC…, S)", KitchenSink.LockHash, KitchenSink.LockSalt, probes),
                    ("no lock", null, null, new[] { "redemption", "x", "" }),
                    ("LockSalt \"not base64!\"", KitchenSink.LockHash, "not base64!", probes),
                    ("LockHash only", KitchenSink.LockHash, null, probes),
                    ("LockHash \"\"", "", KitchenSink.LockSalt, probes),
                };
                var rows = new JsonArray();
                foreach (var (name, hash, salt, ps) in items)
                {
                    var t = new TaskItem { Id = G(3), Name = "locked", LockHash = hash, LockSalt = salt };
                    var verify = new JsonObject();
                    foreach (var p in ps) verify[p] = ItemLockService.Verify(t, p);
                    rows.Add(new JsonObject
                    {
                        ["item"] = name, ["lockHash"] = hash, ["lockSalt"] = salt,
                        ["isLockProtected"] = t.IsLockProtected, ["verify"] = verify,
                    });
                }
                r.Json("result", "verify", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "K09", Family = F, Title = "Protect / TryUnlock / IsGated / Relock / RemoveProtection",
            Settles = new[] { "01 §4.8", "04 §7.8" },
            Run = r =>
            {
                TaskItem Item() => new() { Id = G(3), Name = "locked", Container = new Container { Id = G(103) } };
                var a = Item();
                ItemLockService.Protect(a, "correct horse", "  hint  ");
                r.Mask.Literal(a.LockHash!, "%%HASH32%%");
                r.Mask.Literal(a.LockSalt!, "%%SALT16%%");
                r.Text("protect.hint", "protect-hint", "json", JsonSerializer.Serialize(a, Opts));
                var b = Item();
                ItemLockService.Protect(b, "pw", "   ");
                r.Mask.Literal(b.LockHash!, "%%HASH32%%");
                r.Mask.Literal(b.LockSalt!, "%%SALT16%%");
                r.Text("protect.blankHint", "protect-blank-hint", "json", JsonSerializer.Serialize(b, Opts));
                var c = Item();
                try { ItemLockService.Protect(c, "", null); r.Json("protect.empty", "protect-empty", new JsonObject { ["threw"] = false }, mac: false); }
                catch (Exception ex) { r.Json("protect.empty", "protect-empty", Shapes.ExceptionShape(ex, aaAuthored: true), mac: false); }

                ItemLockService.RelockAll();
                var seq = new JsonArray();
                void Step(string name, Func<bool?> act) => seq.Add(new JsonObject
                {
                    ["step"] = name, ["returned"] = act(), ["isGated"] = ItemLockService.IsGated(a), ["isLockProtected"] = a.IsLockProtected,
                });
                Step("after Protect", () => null);
                Step("TryUnlock(\"wrong\")", () => ItemLockService.TryUnlock(a, "wrong"));
                Step("TryUnlock(\"correct horse\")", () => ItemLockService.TryUnlock(a, "correct horse"));
                Step("Relock", () => { ItemLockService.Relock(a); return null; });
                Step("TryUnlock(\"redemption\")", () => ItemLockService.TryUnlock(a, "redemption"));
                Step("RemoveProtection", () => { ItemLockService.RemoveProtection(a); return null; });
                r.Json("sequence", "sequence", seq);
                r.Text("removed", "removed", "json", JsonSerializer.Serialize(a, Opts));
            },
        };

        yield return new CaseDef
        {
            Id = "K10", Family = F, Compare = "json-semantic", Normative = "record-only",
            Title = "cross-reference: the S11 settings file verifies with PasswordService (see S11)",
            Settles = new[] { "01 DATA-084" },
            Run = r => r.Json("result", "cross-reference", new JsonObject
            {
                ["settingsGolden"] = "settings/S11.settings.golden.json", ["verifyGolden"] = "settings/S11.verify.golden.json",
            }, mac: false),
        };
    }
}
