# XlsxGolden — the XLSX-reader oracle (spec 10 §X.7.6)

For every workbook it is given, XlsxGolden records what the real ClosedXML 0.104.2 and the app's own three cell
renderers produce (COMPAS `CellString`, Shippalm `Cell` + `ExcelDate`, Ports `Cell` + `NormDate` + `NormTime` — the
read-only `AA/Services/*Reader.cs` files, linked and invoked by reflection), as
`mac/Tests/AACoreTests/Fixtures/winfixtures/xlsx/<file name>.golden.json`. The Swift `XlsxWorkbook` + `XlsxRender`
(F2) are then asserted against them by `Tests/AACoreTests/XlsxRead/XlsxReadStructureTests.windowsGoldens` (F2's POC
copies) and `Tests/AACoreTests/WinFixtures/GoldXlsxGoldenTests` (all of them). The **VERIFY** rows of 10 §X.8 are
settled by these goldens; the spec is corrected by an erratum when they disagree.

Inputs:
* `mac/Tests/AACoreTests/Fixtures/xlsx/*.xlsx` — F2's byte copies of the two POC exports;
* `mac/Tests/AACoreTests/Fixtures/winfixtures/xlsx-inputs/*.xlsx` — the synthetic 10 §X.8 workbooks, written by the
  Swift emitter (`Scripts/fixtures.sh emit-xlsx-inputs`, built with the AACore ZIP writer exactly like F2's tests).

## Commands (from `mac/Tools`; .NET 10 SDK, see ../WinFixtures/README.md)

```sh
cd mac/Tools
dotnet run --project XlsxGolden -c Release -- \
    --fixtures ../Tests/AACoreTests/Fixtures/xlsx \
    --fixtures ../Tests/AACoreTests/Fixtures/winfixtures/xlsx-inputs \
    --out ../Tests/AACoreTests/Fixtures/winfixtures/xlsx
```

or `mac/Scripts/fixtures.sh xlsx-golden`. Run it with an en-US (default) or en-GB culture (`--culture en-GB`): the
renderers format through the current culture on Windows exactly as the app does.

## Output

```json
{
  "$meta": { "fixture": "…", "sha256": "…", "closedXml": "0.104.2.0", "runtime": ".NET 10.0.x", "culture": "en-US", "today": "2026-10-02" },
  "<sheet name>": {
    "usedRange": "A1:P2525",
    "cells": {
      "A1": { "kind": "Text", "compas": "No.", "shippalm": "No.", "shippalmDate": "No.", "ports": "No.", "portsDate": "No.", "portsTime": "" },
      "B7": { "kind": "DateTime", "compas": "2023-03-15", "errors": { "ports": "ArgumentException: Serial date 60 is …" } }
    }
  }
}
```

`kind` is ClosedXML's `XLDataType` (`Blank` for an empty cell). A renderer that throws is listed under `errors`
instead of a value. `shippalmDate` (B+) and the time-only Ports cases depend on the day the golden was made
(`$meta.today`): the Swift test injects that day.
