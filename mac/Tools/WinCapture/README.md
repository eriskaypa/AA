# WinCapture — WPF-only and Windows-only captures (Part 2)

Spec: `mac/Docs/Spec/01-data-model-persistence.md` GF.6 (DATA-321…325). Windows only: WinCapture runs WPF's own
`TextRange.Save/Load` and `EditingCommands` on RichTextBoxes configured exactly like AA's `ContainerEditor`, and links
the WPF-bound AA files that produce stored XAML (`ListFormatting.cs`, `HtmlToXamlConverter.cs`, `Sire/SireFlow.cs`,
`Sire/SireModels.cs`, `Sire/TagExtractor.cs` — read-only, never copied). Its output is committed under
`mac/Tests/AACoreTests/Fixtures/xaml/wpf-capture/` and read by `Tests/AACoreTests/WinFixtures/GoldXamlCaptureTests.swift`.

## 1. Capture machine and checkout (GF.6.2)

1. Windows 11 x64, .NET 10 SDK, Git for Windows, PowerShell 7; Microsoft Word, Excel, Outlook (W11 inputs) and Edge
   (W12 inputs). Record `winver`, the display scale and the system theme in the commit message.
2. **LF checkout** so the linked sources hash-match:
   ```powershell
   git -c core.autocrlf=false clone <repo> C:\src\AA
   git -C C:\src\AA checkout mac-port
   ```
3. `cd C:\src\AA\mac\Tools; dotnet run --project WinFixtures -c Release -- verify-sources` must pass.
4. Anything that launches AA uses a scratch data folder — never the operator's real `%LOCALAPPDATA%\AA` (DATA-314):
   `$env:AA_DATA_DIR = 'C:\aa-capture'`.
5. Nothing outside `mac/` may change: the tools build into `mac\Tools\*\bin|obj` (gitignored). If W25 is done, build
   AA with `dotnet build AA\AA.csproj -c Release --artifacts-path mac\Tools\WinCapture\.aa-build`.
   `git status --porcelain -- AA Tests` must print nothing before committing.

## 2. Clipboard inputs (GF.6.6, DATA-322) — once, committed

For each recipe: build the content in the named program, select it, `Ctrl+C`, then immediately:

```powershell
cd C:\src\AA\mac\Tools
dotnet run --project WinCapture -c Release -- dump-clipboard R-1 ..\Tests\AACoreTests\Fixtures\xaml\wpf-capture\inputs
```

| Id | Program | Content |
|---|---|---|
| R-1 | Word | `Plain bold italic underline`, each word styled accordingly |
| R-2 | Word | bulleted list of 3 items, item 2 with one nested item |
| R-3 | Word | numbered list with a nested lettered level |
| R-4 | Word | 2×2 table, bold shaded header row |
| R-5 | Excel | range A1:C3, bold header row, one cell with number format `0.00` |
| R-6 | Word | hyperlink `IMO` → `https://www.imo.org` |
| R-7 | Word | one word underlined **and** struck through; yellow highlight; red text; 11.5 pt |
| R-8 | Word | a small inline picture between two words |
| R-9 | Outlook | two lines separated by Shift+Enter, a tab, a signature line |
| R-10 | Word | `H2O` with subscript 2, `m2` with superscript 2 |
| R-11 | Notepad | plain text only (baseline) |
| H-1 | Edge | a paragraph with `<b>`, `<i>`, `<a>` |
| H-2 | Edge | a nested `<ul>` |
| H-3 | Edge | a `<table>` with `colspan` |
| H-4 | Edge | a selection spanning `<script>`/`<style>` |
| H-5 | Edge | text with CSS `color: rgba(0,0,0,0)` (K-13) |
| H-6 | Edge | an `<hr>` between paragraphs (S-7) |
| H-7 | Edge | nested `div > p` with whitespace between blocks (K-12) |

The `.html` file keeps the raw CF_HTML string (`Version:0.9 StartHTML:…` header included), exactly what
`OnRtbPasting` hands to the converter.

## 3. Automated captures (W01–W18, DATA-321)

```powershell
cd C:\src\AA\mac\Tools
dotnet run --project WinCapture -c Release -- all ..\Tests\AACoreTests\Fixtures\xaml\wpf-capture
```

Writes `<id>.xaml` (UTF-8, no BOM — what `TextRange.Save(DataFormats.Xaml)` produced), `<id>.json-string.txt` (as
stored inside `data.json`), `<id>.meta.json`, `MANIFEST.json` (GF.4.3 shape, family `xaml`) and
`culture-invariance.json` (the same recipes re-run under el-GR and th-TH and compared with en-US).

| Id | What |
|---|---|
| W01 | the root attribute set of a pristine editor; the S-1 body built through the toolbar code paths; load + save |
| W02 | InsertTable (verbatim InsertTable_Click) for 2x2 after a paragraph, 3x4, junk, 0x0, 60x30, an empty document |
| W03 | InsertLink on an empty selection, wrapping a selection, escaping, mailto |
| W04 | ToggleSubscript / ToggleSuperscript (Ctrl+= / Ctrl+Shift+=) |
| W05 | every way a note becomes empty, and whether WPF loads `""` |
| W06 | the built-in key map (CommandManager class input bindings) — if empty, do M-09 |
| W07 | Bold/Italic/Underline toggle semantics; Strike_Click reference comparison (typed / loaded / underline-only) |
| W08 | ToggleBullets/ToggleNumbering/indent/Enter/Tab in lists — raw and after `ListFormatting.Normalise` |
| W09 | `ListFormatting.Build` (numbered, bullets) and a normalised nested list |
| W10 | undo after a programmatic `TextRange.Load` |
| W11 | every `inputs\R-*.rtf`: `TextRange.Load(Rtf)` and the paste path (OnRtbPasting replica) |
| W12 | the 05 §7.1 HTML strings and every `inputs\H-*.html`: `HtmlToXamlConverter.Convert` and the pasted result |
| W13 | combined decorations, a brush with opacity, OverLine, BaselineAlignment.Superscript |
| W14 | InlineUIContainer / BlockUIContainer placeholders |
| W15 | contextual properties on load / paste of a Segoe-rooted section |
| W16 | SIRE question/overview XAML from the real bank and an edited QuestionBodies entry |
| W17 | the lock sentinel `#FFFFE699` round trip |
| W18 | Clear formatting |

## 4. Manual confirmations in the real AA.exe (GF.6.7, DATA-323)

From a PowerShell 7 window: `$env:AA_DATA_DIR = 'C:\aa-capture'`, remove that folder if it exists, then launch the
built or published `AA.exe` from the same window (sign in as usual). For each step create a new Task named after the
capture id, act, press `Ctrl+S`, and continue.

| Id | Actions in the task's note |
|---|---|
| M-01 | type `Check the `, `Ctrl+B`, `main engine`, `Ctrl+B`, ` oil level.`, Enter, `Urgent`; select `Urgent`; `Ctrl+E`; toolbar Text color → red; Highlight → yellow; `Ctrl+U` |
| M-02 | toolbar ▦ Insert table → `2x2` → OK |
| M-03 | type `See `, toolbar 🔗 → `https://www.imo.org` → OK |
| M-04 | type `H2O`, select `2`, `Ctrl+=` |
| M-05 | type `x`, `Ctrl+A`, Delete, wait 1 s |
| M-06 | switch input language to Greek (Win+Space), type `Γειά σου`; switch back, type ` ok` |
| M-07 | a Procedure with two steps (one done, one with a deadline) → export the checklist as XLSX → save `manual\M-07.checklist.xlsx` (W20) |
| M-08 | (optional, W25) import a modified copy of the data → copy the change-preview header/summary text into `manual\M-08.diffwindow.txt` |
| M-09 | only if W06 produced no rows: in a note, try each shortcut of CONT-030 and write the observed effect into `manual\M-09.keys.md` |

Then close AA and extract:

```powershell
$d = Get-Content 'C:\aa-capture\data.json' -Raw | ConvertFrom-Json
$dir = 'C:\src\AA\mac\Tests\AACoreTests\Fixtures\xaml\wpf-capture\manual'; New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($t in $d.Tasks) {
  [IO.File]::WriteAllText("$dir\$($t.Name).xaml", $t.Container.RichTextXaml, [Text.UTF8Encoding]::new($false)) }
Copy-Item 'C:\aa-capture\data.json' "$dir\M-capture.data-json.golden.json"    # synthetic content only (DATA-314)
```

## 5. Windows run of WinFixtures and other Windows-only artefacts (GF.6.8, W19–W22)

```powershell
cd C:\src\AA\mac\Tools
dotnet run --project WinFixtures -c Release -- generate --platform windows --out ..\Tests\AACoreTests\Fixtures\winfixtures
```

* W19 (the DPAPI samples) and W22 (the neutrality cross-check) are part of that run.
* W20 is M-07.
* W21 Explorer ZIP: in a scratch folder put a copy of `winfixtures\json\A02.appdata.golden.json` renamed `data.json`
  and `files\Wärtsilä manual.pdf` (5 bytes); select **both** items (not the folder) → right-click → Send to →
  Compressed (zipped) folder; commit it as `winfixtures\windows\bundles\R20.explorer.bundle.zip`.

## 6. Reverse check (GF.6.9, W23, DATA-325)

After the Mac emitter has written and committed `Fixtures/mac-out/xaml/*.xaml`:

```powershell
dotnet run --project WinCapture -c Release -- load-check ..\Tests\AACoreTests\Fixtures\mac-out\xaml ..\Tests\AACoreTests\Fixtures\xaml\mac-roundtrip
```

Every file must load (`load-check.json` all `ok: true`, exit 0). The `*.wpf-resaved.xaml` files are compared on the
Mac with `xml-canonical` against the Mac input; differences are recorded, not failures, except lost text or a lost
lock sentinel, which fail (`GoldXamlCaptureTests.macRoundTrip`).

## 7. Commit (GF.6.10)

Only paths under `mac/` on `mac-port` (the pre-commit hook rejects anything else). Message:
`Capture WPF fixtures (<winver>, WPF <PresentationFramework version>)`.
