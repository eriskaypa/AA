// XlsxGolden (spec 10 §X.7.6): for every workbook in the --fixtures folders, writes `<file name>.golden.json` under
// --out: per worksheet, the used range and, for every cell in it, the ClosedXML data type and the strings the app's
// renderers produce — A = COMPAS CellString, B = Shippalm Cell, B+ = Shippalm ExcelDate(B), C = Ports Cell,
// C·D = Ports NormDate(C), C·T = Ports NormTime(C) — plus any exception message. Run it on Windows (or macOS) with
// an en-US or en-GB culture (pinned to en-US unless --culture says otherwise).
//
//   dotnet run --project XlsxGolden -c Release -- --fixtures <dir> [--fixtures <dir>…] --out <dir> [--culture en-US]
//
// Output shape (read by Tests/AACoreTests/XlsxRead/XlsxReadStructureTests.windowsGoldens and
// Tests/AACoreTests/WinFixtures/GoldXlsxGoldenTests):
//   { "$meta": {...}, "<sheet name>": { "usedRange": "A1:C3" | null, "cells": { "A1": { "kind": "Number",
//     "compas": "…", "shippalm": "…", "shippalmDate": "…", "ports": "…", "portsDate": "…", "portsTime": "…",
//     "errors": { "compas": "…" } } } } }
// or { "$meta": {...}, "$error": { "type": "…", "message": "…" } } when the workbook does not open.
using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Services;
using ClosedXML.Excel;

namespace XlsxGolden;

internal static class Program
{
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true, IndentSize = 2, NewLine = "\n", Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private const BindingFlags Priv = BindingFlags.NonPublic | BindingFlags.Static;

    private static readonly MethodInfo CompasCell = typeof(CompasReader).GetMethod("CellString", Priv)!;
    private static readonly MethodInfo ShippalmCell = typeof(ShippalmReader).GetMethod("Cell", Priv)!;
    private static readonly MethodInfo ShippalmExcelDate = typeof(ShippalmReader).GetMethod("ExcelDate", Priv)!;
    private static readonly MethodInfo PortsCell = typeof(PortCallReader).GetMethod("Cell", Priv)!;
    private static readonly MethodInfo PortsNormDate = typeof(PortCallReader).GetMethod("NormDate", Priv)!;
    private static readonly MethodInfo PortsNormTime = typeof(PortCallReader).GetMethod("NormTime", Priv)!;

    private static int Main(string[] args)
    {
        var fixtures = new List<string>();
        string? outDir = null;
        var culture = "en-US";
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--fixtures" when i + 1 < args.Length: fixtures.Add(args[++i]); break;
                case "--out" when i + 1 < args.Length: outDir = args[++i]; break;
                case "--culture" when i + 1 < args.Length: culture = args[++i]; break;
                default:
                    Console.Error.WriteLine("usage: XlsxGolden --fixtures <dir> [--fixtures <dir>…] --out <dir> [--culture en-US|en-GB]");
                    return 2;
            }
        }
        if (fixtures.Count == 0 || outDir == null)
        {
            Console.Error.WriteLine("usage: XlsxGolden --fixtures <dir> [--fixtures <dir>…] --out <dir> [--culture en-US|en-GB]");
            return 2;
        }
        var c = new CultureInfo(culture);
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.DefaultThreadCurrentUICulture = c;
        CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = c;
        Directory.CreateDirectory(outDir);

        int written = 0;
        foreach (var dir in fixtures)
        {
            if (!Directory.Exists(dir)) { Console.Error.WriteLine($"XlsxGolden: no folder {dir} — skipped"); continue; }
            foreach (var file in Directory.GetFiles(dir, "*.xlsx").OrderBy(x => x, StringComparer.Ordinal))
            {
                var node = Golden(file, culture);
                File.WriteAllText(Path.Combine(outDir, Path.GetFileName(file) + ".golden.json"), node.ToJsonString(Json) + "\n",
                                  new System.Text.UTF8Encoding(false));
                written++;
                Console.WriteLine($"  {Path.GetFileName(file)}");
            }
        }
        Console.WriteLine($"XlsxGolden: {written} golden(s) in {outDir}");
        return written > 0 ? 0 : 1;
    }

    private static JsonObject Golden(string file, string culture)
    {
        // Hash from a full read that is closed again before ClosedXML opens the file (no overlapping handles).
        var sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))).ToLowerInvariant();
        var root = new JsonObject
        {
            ["$meta"] = new JsonObject
            {
                ["fixture"] = Path.GetFileName(file),
                ["sha256"] = sha256,
                ["closedXml"] = typeof(XLWorkbook).Assembly.GetName().Version?.ToString(),
                ["runtime"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
                ["culture"] = culture,
                ["today"] = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            },
        };
        XLWorkbook wb;
        try { wb = new XLWorkbook(file); }
        catch (Exception ex)
        {
            root["$error"] = new JsonObject { ["type"] = ex.GetType().FullName, ["message"] = ex.Message };
            return root;
        }
        using (wb)
        {
            foreach (var ws in wb.Worksheets)
            {
                var sheet = new JsonObject();
                var used = ws.RangeUsed();
                sheet["usedRange"] = used?.RangeAddress.ToStringRelative(includeSheet: false);
                var cells = new JsonObject();
                if (used != null)
                {
                    int r0 = used.FirstRow().RowNumber(), r1 = used.LastRow().RowNumber();
                    int c0 = used.FirstColumn().ColumnNumber(), c1 = used.LastColumn().ColumnNumber();
                    for (int r = r0; r <= r1; r++)
                        for (int col = c0; col <= c1; col++)
                        {
                            var cell = ws.Cell(r, col);
                            var o = new JsonObject { ["kind"] = cell.IsEmpty() ? "Blank" : cell.DataType.ToString() };
                            var errors = new JsonObject();
                            string? Try(string key, Func<string> f)
                            {
                                try { var s = f(); o[key] = s; return s; }
                                catch (Exception ex)
                                {
                                    var inner = ex is TargetInvocationException tie && tie.InnerException != null ? tie.InnerException : ex;
                                    errors[key] = inner.GetType().Name + ": " + inner.Message;
                                    return null;
                                }
                            }
                            Try("compas", () => (string)CompasCell.Invoke(null, new object[] { cell })!);
                            var b = Try("shippalm", () => (string)ShippalmCell.Invoke(null, new object[] { ws, r, col })!);
                            if (b != null) Try("shippalmDate", () => (string)ShippalmExcelDate.Invoke(null, new object[] { b })!);
                            var cText = Try("ports", () => (string)PortsCell.Invoke(null, new object[] { ws, r, col })!);
                            if (cText != null)
                            {
                                Try("portsDate", () => (string)PortsNormDate.Invoke(null, new object[] { cText })!);
                                Try("portsTime", () => (string)PortsNormTime.Invoke(null, new object[] { cText })!);
                            }
                            if (errors.Count > 0) o["errors"] = errors;
                            cells[cell.Address.ToStringRelative()] = o;
                        }
                }
                sheet["cells"] = cells;
                root[ws.Name] = sheet;
            }
        }
        return root;
    }
}
