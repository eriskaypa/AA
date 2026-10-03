# WinFixtures — the golden-fixture oracle (Part 1)

Spec: `mac/Docs/Spec/01-data-model-persistence.md`, Addendum "Golden-fixture plan" (GF.0–GF.10, DATA-300…326).

WinFixtures compiles the **unmodified, read-only** Windows C# files (linked from `../../../AA/…`, never copied)
into a plain `net10.0` console, runs them, and records what that code actually does as goldens under
`mac/Tests/AACoreTests/Fixtures/winfixtures/`. The Swift tests in `mac/Tests/AACoreTests/WinFixtures/` reproduce
every case on the Mac and compare byte-for-byte (or by a defined normalised mode). It is an **oracle, not a port**:
nothing here is built by `mac/Package.swift`, linked into AA.app or needed to build, run or unit-test the Mac app.

## Requirements

* .NET 10 SDK (the band pinned by `mac/Tools/global.json`, which is only honoured when `dotnet` runs from
  `mac/Tools`; every command below and `mac/Scripts/fixtures.sh` does that).
  * macOS: `brew install --cask dotnet-sdk`, or the official script into the gitignored local folder:
    `curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir mac/Tools/.dotnet`
  * Windows: the .NET 10 SDK installer; PowerShell 7.
* An **LF checkout** (the linked sources are hash-pinned): `git -c core.autocrlf=false clone <repo>`, then check out
  `mac-port`. `verify-sources` fails on a CRLF checkout.
* NuGet access on first build (ClosedXML 0.104.2, PDFsharp-MigraDoc 6.2.0 — the versions of `AA/AA.csproj`).

## Commands (from `mac/Tools`)

```sh
cd mac/Tools

# 1. DATA-301: the linked files match mac/Docs/original-source-checksums.sha256 (exit 1 otherwise)
dotnet run --project WinFixtures -c Release -- verify-sources

# 2. Generate every family on macOS/Linux (the `any` and `unix` cases, six time zones for the date cases)
dotnet run --project WinFixtures -c Release -- generate --out ../Tests/AACoreTests/Fixtures/winfixtures

#    …or a subset of families (a json, b settings, c bundles, d crypto, e services, f ext)
dotnet run --project WinFixtures -c Release -- generate --out ../Tests/AACoreTests/Fixtures/winfixtures --families a,d

# 3. CI / review: regenerate into a temp tree and diff against the committed goldens (exit 1 on any difference)
dotnet run --project WinFixtures -c Release -- generate --out ../Tests/AACoreTests/Fixtures/winfixtures --verify-only

# 4. Recompute specConflicts[] against the literals quoted in the specs (also done by every unix generate)
dotnet run --project WinFixtures -c Release -- selfcheck --out ../Tests/AACoreTests/Fixtures/winfixtures

# 5. Reverse check of what the Mac writes (after `Scripts/fixtures.sh emit-mac-out` on the Mac)
dotnet run --project WinFixtures -c Release -- check-mac ../Tests/AACoreTests/Fixtures/mac-out --report ../Tests/AACoreTests/Fixtures/mac-out/check-report.unix.json

# The case catalogue
dotnet run --project WinFixtures -c Release -- list
```

On **Windows** (GF.6.8, W22: `platform: windows` cases, the DPAPI sample W19, the neutrality cross-check):

```powershell
cd C:\src\AA\mac\Tools
dotnet run --project WinFixtures -c Release -- verify-sources
dotnet run --project WinFixtures -c Release -- generate --platform windows --out ..\Tests\AACoreTests\Fixtures\winfixtures
dotnet run --project WinFixtures -c Release -- check-mac ..\Tests\AACoreTests\Fixtures\mac-out --report ..\Tests\AACoreTests\Fixtures\mac-out\check-report.windows.json --platform windows
git status --porcelain -- ..\..\AA ..\..\Tests     # must print nothing (rule zero)
```

`mac/Scripts/fixtures.sh` wraps all of these (`verify-sources`, `generate`, `verify-generated`, `selfcheck`,
`xlsx-golden`, `check-mac`, `verify`, `require`, `emit-mac-out`, `emit-xlsx-inputs`, `real-data`, `ci`, `status`).

No process of the tool ever resolves the operator's real `%LOCALAPPDATA%\AA` (DATA-314): the parent process pins
`AA_DATA_DIR` to a scratch path (never created) before the case catalogue touches `DataStore`, and every child gets
its own scratch data folder from the driver.

## What a run does (GF.3.4)

1. `verify-sources` or abort.
2. The driver re-launches itself once per (family, time zone) group — and once per case for the settings and
   bundle-matrix cases — with a fresh `AA_DATA_DIR` (`/tmp/aa-winfixtures/<run>/<group>` or
   `C:\aa-winfixtures\<run>\<group>`), `TZ=<zone>` on Unix, `LANG/LC_ALL=en_US.UTF-8` and the en-US culture.
   `DataStore.AppFolder` is a static read once and `TimeZoneInfo.Local` is cached per process: hence the processes.
3. Each case resets the world (empty data folder, `LoadSettings`, no app password, every item re-locked), builds its
   inputs, calls the linked C#, masks the values that are random or clock-derived by design (`%%NEWGUID:n%%`,
   `%%NOWUTC%%`, `%%DATADIR%%`, …, GF.4.5) and writes outputs + a case record.
4. The records are merged into `MANIFEST.json` (cases sorted by id), `selfcheck` (unix) or the neutrality
   cross-check (windows) runs, and the staging tree replaces the fixture tree only when every group succeeded — a
   partial run is never committed. Two consecutive runs are byte-identical except `generatedAtUtc` (and the
   `dependsOnToday` / `nonDeterministic` outputs, listed in the manifest).

Each platform run owns only its own part of the tree: the unix run owns `json/ settings/ bundles/ crypto/
services/ ext/` and the `any`/`unix` records; the windows run owns `windows/` and the `platform: windows` records
(ids with a `w` suffix, e.g. `A25xw`). `inputs/` keeps the authored inputs (`A05.input.json`, `A10.input.json`,
`E11.rows.json`); `xlsx/` and `xlsx-inputs/` belong to XlsxGolden and the Swift emitter and are never touched.
`windows/bundles/R20.explorer.bundle.zip` (W21, made by hand with Explorer — `mac/Tools/WinCapture/README.md` §5) is
an authored Windows artefact: every run carries it over, and while it is committed the bundle family adds the matrix
rows `M.R20.*` and `P.R20` (a case whose `RequiresFile` is absent is skipped without a record).

## Files

| Path | Role |
|---|---|
| `WinFixtures.csproj` | GF.3.1 — linked sources, ClosedXML, PDFsharp-MigraDoc, InvariantGlobalization=false |
| `Shims/DispatcherTimer.cs` | GF.3.2 — the only shim (lets AppRepository compile; never ticks) |
| `Program.cs` | GF.3.3 — CLI |
| `Support/Driver.cs` | GF.3.4 — groups, child processes, staging, merge, neutrality, `--verify-only` diff |
| `Support/World.cs` | GF.3.5 — culture pin, `ResetWorld`, environment assertions, GF.4.7 shapes |
| `Support/Fx.cs` | G(n) ids, the fixed dates, the app's own `Opts`/`TrashOpts` (reflection), GF.3.8 expectation JSON |
| `Support/Masker.cs` | GF.3.7 masking (exact-value substitution + automatic masking against a baseline) |
| `Support/CaseRun.cs` | case definitions, the per-case context, GF.4.4 case record, the catalogue |
| `Support/Derive.cs` | derived Mac expectations (null-as-default, nested-unknown superset) |
| `Support/ZipInspect.cs` | GF.3.9 raw ZIP manifest + payloads |
| `Support/SourcePin.cs` | DATA-301 |
| `Support/SelfCheck.cs` | GF.3.10 |
| `Support/CheckMac.cs` | GF.3.11 |
| `Builders/KitchenSink.cs` | GF.5.a KS and the A04 defaults database |
| `Builders/Corpora.cs` | services data sets (01 §7.8, 02 §7.7, 02 §7.8) |
| `Cases/FamilyA…F.cs` | GF.5.a–f |

## Privacy (DATA-314)

Every fixture is synthetic. A real `data.json` (crew passports, dates of birth, next of kin) is never committed.
The optional local-only round trip of a real file is a Swift test: `AA_REAL_DATA_JSON=/path/to/data.json swift
test --filter GoldRealDataRoundTrip` (or `Scripts/fixtures.sh real-data /path/to/data.json`) — it reads a copy in a
temporary folder, reports pass/fail and byte offsets only, and writes nothing.
