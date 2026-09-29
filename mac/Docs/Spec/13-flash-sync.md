# 13 — Flash Sync (QR fountain transfer) — porting spec

Subsystem prefix: **FLASH-**. Status of the Windows source this spec was written from: branch `mac-port`,
commit `37cdab0` ("Flash Sync: verify against iOS, fix the Ui split, add interop harness").

**Sources read in full:** `AA/FlashSync/FlashSyncCodec.cs`, `FlashSyncEncoder.cs`, `FlashSyncDecoder.cs`,
`FlashChangeSet.cs`, `FlashSyncStore.cs`, `FlashQr.cs`, `FlashQrDecoder.cs`, `FlashCamera.cs`,
`AA/Views/FlashSyncWindow.xaml` + `.xaml.cs`, `QR_SYNC_PROTOCOL.md` (all 824 lines),
`Tests/FlashSync.Interop/Program.cs` + `.csproj`, the Flash Sync sections of `PROGRESS.md`
("Flash Sync with iPhone (QR fountain)…" and "Flash Sync: verified against the iPhone, and the `Ui` split
fixed on both sides"), plus the call-graph pieces in `AA/MainWindow.xaml(.cs)`, `AA/AA.csproj`,
`AA/Services/DataStore.cs` (settings DTO, `SerializeForSave`, `ApplySyncedData`, `ImportFolderFromZip`),
`AA/Services/AppRepository.cs` (`Save`) and `AA/Models/Models.cs` (`AppData`, `UiState`, `TrashedItem`).

**Normative references.** `QR_SYNC_PROTOCOL.md` (repo root) is the wire contract shared with the shipping iOS
app. Where this spec quotes it, the protocol file wins on wire matters; where the Windows code differs from the
protocol text, this spec says so explicitly (see §8 "Windows quirks, deviations and open questions").

**All the Python-generated vectors in §7 were produced by a line-for-line replica of the C# code that first
reproduces every vector in `QR_SYNC_PROTOCOL.md`** (so they're trustworthy), and the DEFLATE facts were checked
against Apple's `Compression` framework on this machine.

---

## 1. Overview

### 1.1 What it is

Flash Sync moves the **text, changes and formatting** of the database (`data.json`) plus the shareable part of
`settings.json` between two AA installations **with no cable, network, account or shared folder**: one machine
flashes a rapid, endless sequence of QR codes on its screen, the other films it with a camera. It is a
**one-way optical channel**, so it uses a **fountain (rateless) code**: every frame is the XOR of a
pseudo-random subset of source chunks, and the receiver needs *any* ≈K·(1+ε) distinct frames, not specific ones.
Attachments (`files/`) never travel — same contract as the text-only `.aaz` export.

Two payload kinds:

* **Change set** (kind 0) — a structural diff of the current `data.json` tree + `settings.json` against a
  **baseline** (the state the peer last confirmed receiving). Typical edit: 1–4 frames.
* **Full snapshot** (kind 1) — an envelope carrying the whole `data.json` (minus per-device keys) and the
  shareable settings. Used for the first pairing (no baseline yet). The whole 3.1 MB database DEFLATEs to
  ~437 KB → K≈486 chunks → ~14–50 s at 12–15 fps.

The peer on Windows is always described as "the iPhone" (the iOS app, reached on the phone via
**More ▸ Backup & Transfer ▸ Flash Sync with PC**). The protocol is symmetric, so the Mac build can pair with
the iPhone **and** with the Windows app (Windows "Send to iPhone" → Mac "Receive", and vice versa).

### 1.2 Where it sits

* Opened from **File ▸ Flash Sync with iPhone (QR)...** (`AA/MainWindow.xaml:67-68`, handler
  `MenuFlashSync_Click` in `AA/MainWindow.xaml.cs:474-487`). It sits in the File menu after the Google-Drive
  group ("Check Google Drive for newer save"), between two separators, just above **Exit**.
* The window is `AA.Views.FlashSyncWindow`, shown **modally** (`ShowDialog`, `Owner = MainWindow`).
* Layers (Windows):

| layer | file | platform-neutral? |
|---|---|---|
| Codec: Base45, CRC-32, raw DEFLATE, xorshift32, degree table, indices, framing | `FlashSync/FlashSyncCodec.cs` | yes |
| Fountain encoder | `FlashSync/FlashSyncEncoder.cs` | yes |
| Peeling decoder | `FlashSync/FlashSyncDecoder.cs` | yes |
| Change set / snapshot build + apply over JSON trees | `FlashSync/FlashChangeSet.cs` | yes |
| Baseline + bridge to DataStore / settings | `FlashSync/FlashSyncStore.cs` | file I/O only |
| QR generation + raster (Nayuki via Net.Codecrete, WPF `BitmapSource`) | `FlashSync/FlashQr.cs` | no (WPF imaging) |
| QR reading (OpenCV WeChat CNN detector) | `FlashSync/FlashQrDecoder.cs` + `FlashSync/Models/*` | no (OpenCV win) |
| Webcam capture (OpenCV DirectShow) | `FlashSync/FlashCamera.cs` | no |
| UI (Send / Receive tabs, keep-awake P/Invoke) | `Views/FlashSyncWindow.xaml(.cs)` | no |
| Conformance / interop CLI | `Tests/FlashSync.Interop/Program.cs` | yes |

On the Mac all of the "yes" rows go into `AACore/FlashSync/` (pure Swift over the AACore `JSONValue` tree, no
AppKit), the QR generator goes into `AACore/FlashSync/QR/` (pure Swift port of Nayuki's algorithm), and camera /
Vision / display / keep-awake go into the `AA` app target.

---

## 2. Feature checklist

Exact user-visible strings are quoted verbatim from the Windows build. Where the Mac should adapt wording
(e.g. "this PC" → "this Mac") both are given. `\n` = line break inside a message box.

### 2.1 Entry point and window

**FLASH-001 — File-menu entry.** Menu item header `Flash S_ync with iPhone (QR)...` (access key **y**; no
keyboard shortcut). Tooltip: `Transfer your text, changes and formatting to or from the iPhone app by flashing
QR codes on screen — no network, no cable, no Wi-Fi. Attachments are not included.` Mac: **File ▸ Flash Sync
with iPhone (QR)…** (typographic ellipsis), same help tag; SF Symbol `qrcode`. No ⌘-shortcut exists on Windows;
the Mac need not add one (if one is added, `⌥⌘Y` is free — optional).

**FLASH-002 — Flush and save before opening.** Before the window opens, the main window calls
`FlushAllEditors()` (so an in-progress rich-text edit reaches the model) and, if the repository is dirty,
`_repo.Save()` — a **synchronous** save that blocks until the file is on disk (`AppRepository.Save`, waits up to
15 s). Both calls are wrapped in `try { } catch { }` (failures ignored). Reason: Flash Sync reads the database
**from disk**, so an unsaved edit would otherwise be missing from what is flashed. Mac: flush every editor in
every window (main + item windows) and perform a blocking save before the Flash Sync window prepares anything.

**FLASH-003 — Window chrome and layout.** Title `Flash Sync with iPhone`; 920 × 760, centred on owner, app icon;
outer margin 12. Top: bold 16-pt header `Flash Sync with iPhone` in the **Accent** brush; below it, muted,
wrapping intro text:
`Moves your text, changes and formatting between this PC and the iPhone app by flashing QR codes on screen — no
network, no cable, no Wi-Fi. Attachments are not carried; files already on the other device are left exactly
as they are.` (Mac: "…between this Mac and the iPhone app…"). Below: a TabControl with two tabs,
`Send to iPhone` and `Receive from iPhone` (FLASH-010…, FLASH-030…). Each tab body has margin 10.

**FLASH-004 — Modality.** `ShowDialog()` — the main window (and every other AA window on the UI thread) is
disabled while Flash Sync is open, so no edits can happen concurrently. See §6.6 for the Mac approach.

**FLASH-005 — Closing.** `Window_Closing` (`FlashSyncWindow.xaml.cs:344-350`): stop flashing (timer stop +
release keep-awake), stop the camera, dispose the QR reader. Closing is never cancelled. Nothing is written on
close; an un-confirmed send leaves the baseline untouched.

**FLASH-006 — Main window reload after an apply.** The window raises `DataApplied(AppData)` after a successful
apply; the main window handler calls `LoadDataAndInitUi()` (reload settings + data from disk, recreate the
repository, re-init every page, restore UI state) and sets the status bar to
`Applied changes received from the iPhone`. Undo history is lost (new repository) — a Flash Sync apply is **not
undoable**.

### 2.2 Send tab ("Send to iPhone")

**FLASH-010 — Prepare the outgoing payload when the window loads.** On `Loaded` → `PrepareSend()`
(`:53-77`) and `PopulateCameras()`. `PrepareSend` calls `FlashSyncStore.BuildOutgoing(DataStore.AppIdentity)`:

* baseline exists → change set vs baseline; if nothing changed → **nothing to send**;
* no baseline (or unreadable) → **full snapshot**.

On a payload it creates a `FlashEncoder` with a **new random session** (FLASH-022), stores `K`, and captures the
**pending baseline** (FLASH-021). Start button enabled. (A `FlashEncoder` constructor exception — only "payload
too large", >65535 chunks — is not caught here.)

**FLASH-011 — Send summary text** (`SendSummary`, wrapping, above the buttons). Exactly one of:

* nothing to send: `Nothing to send — the iPhone already has everything, as of the last transfer it confirmed.`
  (and **Start flashing** is disabled);
* snapshot: `First transfer to this iPhone, so the whole database goes across: {K} pieces, about {estimate}.`
  (no singular form for "pieces" here);
* change set: `Sending your changes since the last confirmed transfer — {label}. {K} piece{s}, about {estimate}.`
  where `{s}` is empty when K == 1, `s` otherwise, and `{label}` is `FlashChangeSet.Summarize(cs)` (FLASH-093).

`{estimate}` = `EstimateSeconds(K)` (`:79-85`): `fps = slider value (12 if ≤0)`;
`secs = ceil(K × 1.35 / fps) + 1` (integer); `secs < 60` → `"{secs} seconds"` (always plural, minimum is 2),
else `"{secs/60} min {secs%60} s"`. It is computed **once**, when the summary is built, from the slider value at
that moment (moving the slider later does not refresh it).

**FLASH-012 — Send hint.** Muted, wrapping: `On the iPhone: More ▸ Backup & Transfer ▸ Flash Sync with PC ▸
Receive, then point it at this window.` (Keep verbatim on Mac — it names the iPhone's own menu path.)

**FLASH-013 — Start flashing.** Bold button `Start flashing`. Click (`:87-96`): if no encoder → no-op; else start
the frame timer, disable Start, enable **Stop**, enable **The iPhone says it got it**, and request
keep-awake (display + system, FLASH-024). The first frame appears one timer interval after the click (the timer
fires first; there is no immediate draw).

**FLASH-014 — Stop.** Button `Stop` (initially disabled). `StopFlashing()` (`:100-106`): stop the timer; Start
re-enabled iff an encoder exists; Stop disabled; keep-awake released. The confirm button is **not** disabled by
Stop (the user may stop and then confirm). The last QR stays displayed. Frame/seed counters are not reset —
pressing Start again continues the same endless stream (same session).

**FLASH-015 — Speed slider.** Muted label `Speed`, a slider 6…15, default 12, integer ticks (snap), width 120;
value text `{fps} / sec` (e.g. `12 / sec`). Changing it (`Fps_Changed`, ignored until the window is loaded)
sets the timer interval to `1000.0 / fps` ms immediately, including while flashing. Not persisted (every open
starts at 12). The protocol recommends 8–15; Windows allows 6–15 — keep 6–15.

**FLASH-016 — QR display.** Fill area of the tab: a **white** plate (`Background="White"` regardless of theme),
corner radius 4, padding 18, min height 300, containing the QR image with nearest-neighbour scaling,
`Stretch="Uniform"` (fit, keep square), snapped to device pixels. The bitmap itself is rendered at 1 px per
module **with a 4-module white quiet zone** (FLASH-071), black modules on white, then up-scaled with
nearest-neighbour. Each frame is fitted independently, so the small manifest symbol (version 2–7) is drawn with
much bigger modules than the version-22 data symbols — expected. Before the first Start the plate is empty white.

**FLASH-017 — Flashing progress.** Muted text under the plate after every frame:
`Flashing — {framesShown} frames shown, {passes} full pass{es}. Keep going until the iPhone says it is done.`
where `passes = framesShown / max(1, K)` (integer division; `framesShown` counts manifest frames too) and
`{es}` is empty when passes == 1, `es` otherwise (so `0 full passes`, `1 full pass`, `2 full passes`).
`framesShown` is a window-lifetime counter — it is **not** reset by a confirm or a re-prepare (Windows quirk; see
§8 Q-9).

**FLASH-018 — QR draw failure.** If generating/drawing a frame throws: stop flashing and show a warning box,
title `Flash Sync`, text `Could not draw the QR code: {exception message}`, OK only. (Practically unreachable:
frames are ≤1367 alphanumeric characters, far below QR version 40 capacity.)

**FLASH-019 — "The iPhone says it got it".** Button (padding 14,6, left-aligned, initially disabled; enabled by
Start). Tooltip: `Press this only once the iPhone reports the transfer completed. It records what the phone now
has, so next time only your newer changes need to be sent.` Under it, muted wrapping text: `Only press that
when the phone has actually confirmed. It is what makes the next sync short — and if it is pressed early, the
changes it skips would never be sent again.`
Click (`Confirmed_Click`, `:139-157`): if there is no pending baseline → no-op. Otherwise a Yes/No question box,
**default No**, title `Confirm the iPhone received it`, text:
`Has the iPhone actually reported that the transfer finished?\n\nOnly confirm if it has. This records what the
phone now holds, so future syncs send just your newer changes. Confirming too early would skip the changes it
never received, and they would not be sent again.`
Anything but Yes → nothing happens. Yes → FLASH-020.

**FLASH-020 — After confirmation.** In order: `FlashSyncStore.WriteBaseline(pending.Data, pending.Settings)`;
stop flashing; disable the confirm button; drop the encoder; clear the progress text; `PrepareSend()` again
(normally now yields "Nothing to send — …"); information box title `Flash Sync`, text
`Recorded. Next time only your newer changes need to go across.`

**FLASH-021 — Pending baseline = the trees as they were when the payload was built.** In `PrepareSend`, right
after building the payload, the window captures `FlashSyncStore.ReadDataTree()` and `ReadSettingsTree()` —
the **full, unstripped** trees (per-device keys and excluded settings included). That, not the state at confirm
time, becomes the baseline on confirmation. Consequence: any edit made after the payload was built is *not* in
the baseline and will be sent next time. (Windows re-reads from disk for this capture; the payload was built
from an identical earlier read.) The baseline advances **only** on explicit user confirmation — never on a
guess (class remarks of `FlashSyncStore`).

**FLASH-022 — Session id.** Every `PrepareSend` that yields a payload creates a new encoder with
`FlashEncoder.NewSession()` = uniform random integer **1…65535** (never 0) (`FlashSyncEncoder.cs:72`). The
receiver discards everything it has when it sees a manifest with a different session or CRC.

**FLASH-023 — Frame stream.** Each timer tick shows `encoder.Next()` (FLASH-067): a manifest frame at emitted
positions 0, 12, 24, …; data frames otherwise with seeds 0, 1, 2, … (separate counter). The stream never ends;
the systematic prefix means one clean pass (K data frames + ⌈K/11⌉ manifests) is enough for a clean capture.

**FLASH-024 — Keep the display awake while flashing.** Start → `SetThreadExecutionState(ES_CONTINUOUS |
ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)`; Stop / close / confirm → `SetThreadExecutionState(ES_CONTINUOUS)`.
Failures ignored. (No keep-awake while *receiving*.)

### 2.3 Receive tab ("Receive from iPhone")

**FLASH-030 — Camera picker.** Row: muted label `Camera`, a combo box (width 190), bold `Start camera`, `Stop`
(initially disabled), `Rescan`. `PopulateCameras()` (`:161-172`) clears the list and probes DirectShow indices
0…4 (`FlashCamera.Enumerate(maxProbe: 5)`); each index that opens is listed as `Default camera` (index 0) or
`Camera {index+1}` (e.g. `Camera 2`). DirectShow gives no reliable names, so names are positional. First entry
selected.

**FLASH-031 — No camera.** If none open: status text `No camera found. Plug one in and press Rescan — or use the
Send tab, which needs no camera at all.` and **Start camera** disabled.

**FLASH-032 — Rescan.** Enables **Start camera**, then re-runs `PopulateCameras()` (which may disable it again).
Windows does not disable Rescan while capturing (a latent bug — see §8 Q-7); the Mac must disable Rescan (and the
picker) while the camera runs.

**FLASH-033 — Start camera.** (`:185-213`) Requires a selected camera. Lazily creates the QR reader; failure →
error box title `Flash Sync`, text `The QR reader could not start: {message}`, and abort. Then: **a fresh
decoder** (any previous partial progress is discarded), a new camera object; status
`Looking for the iPhone's screen...` (three ASCII dots); progress bar 0; label cleared. Start the camera; on
failure the error callback shows the message (FLASH-039) and nothing else changes. On success: Start disabled,
Stop enabled, picker disabled.

**FLASH-034 — Capture settings.** Requested (best-effort, failures ignored): 1920 × 1080, 30 fps, driver buffer
of 1 frame ("freshest frame, not a backlog"). Capture runs on a background thread named `FlashSync capture`;
decoding happens on that thread, never on the UI thread.

**FLASH-035 — Stop camera.** `StopCamera()` (`:217-224`): stop capture (thread join ≤ 500 ms, release device),
Start re-enabled iff the list is non-empty, Stop disabled, picker enabled. The decoder's partial state is kept
until the next Start (which replaces it).

**FLASH-036 — Live preview.** Fill area: **black** plate, corner radius 4, min height 280, the camera image
fitted (`Stretch="Uniform"`, default smooth scaling). The preview is a comfort feature: pushed at most once per
**100 ms** (throttled on the capture thread) so it never competes with decoding. Not mirrored.

**FLASH-037 — Per-frame decoding.** Every captured frame is converted to grayscale and run through the detector,
which returns **every** QR string visible (multiple per frame allowed). **Every** string is fed to the fountain
decoder, which itself rejects foreign codes, frames of other sessions and duplicate seeds. Frames are ignored
entirely while an apply is in progress (`_applying`).

**FLASH-038 — Receive progress.** Bottom area: a progress bar (height 16), a muted wrapping status line, and a
bold wrapping label line. After each frame (marshalled to the UI thread):

* once a manifest is known (K > 0): bar maximum = K, value = solved; status
  `Receiving — {solved} of {K} pieces. Hold steady.`; if the manifest label is not blank, label line
  `Incoming: {label}` (a blank label leaves the line unchanged);
* before any manifest: status `Looking for the iPhone's screen...`.

**FLASH-039 — Camera errors** (shown in the status line after the camera is stopped via `OnCameraError`):

| condition | message |
|---|---|
| device will not open | `That camera could not be opened. Another app may be using it.` |
| exception while starting | `Could not start the camera: {message}` |
| >120 consecutive empty reads (10 ms apart, ≈1.2 s+) | `The camera stopped sending frames.` |
| exception inside the capture loop | `Camera error: {message}` |

**FLASH-040 — Receive hint.** Muted, wrapping: `On the iPhone: More ▸ Backup & Transfer ▸ Flash Sync with PC ▸
Send. Hold the phone steady, fairly close, screen bright and square-on to the camera. Missed frames are normal —
the transfer repairs itself and simply takes a moment longer.`

**FLASH-041 — Completion.** When the decoder reports complete (and no apply is running), the UI thread sets
`_applying = true` and runs `FinishReceive()` (`:294-342`): stop the camera first, then `decoder.Finish()`
(reassemble, truncate to `codedBytes`, CRC-32 check, inflate to exactly `rawBytes`).

**FLASH-042 — Damaged transfer.** `Finish()` returned null (CRC mismatch, inflate failure, any bound violated):
status `The transfer arrived damaged, so nothing was changed. Start the iPhone sending again.`; nothing is
written.

**FLASH-043 — Unreadable payload.** Payload not valid JSON or not a JSON object: status
`That transfer was not readable as Flash Sync data. Nothing was changed.`

**FLASH-044 — Review before apply (never apply silently).** Question box, **Yes/No, default No**, title
`Apply the received changes?`, text:
`Received from the iPhone:\n\n    {summary}{warning}\n\nApply it now?` — the summary is indented by four spaces;
`{summary}` is `the sender's entire database (replaces yours)` for a snapshot, else
`FlashChangeSet.Summarize(changeSet)`; `{warning}` is empty for a change set and, for a snapshot:
`\n\nThis REPLACES your current database with the iPhone's copy. Anything on this PC that is not on the phone will
be lost.` (Mac: "…Anything on this Mac that is not on the phone will be lost.")

**FLASH-045 — Discard.** Answer ≠ Yes → status `Discarded — nothing was changed.`; the decoded payload is
dropped (a new Start camera begins from scratch).

**FLASH-046 — Apply.** Yes → `FlashSyncStore.Apply(change)` (FLASH-105); status `Applied. {summary}`; raise
`DataApplied` (FLASH-006); `PrepareSend()` again ("the baseline moved, so what is left to send has changed too").

**FLASH-047 — Apply failure.** Exception → error box title `Flash Sync`, text
`Could not apply the transfer: {message}`; status `Failed to apply — your data was not changed.` (That promise
is not strictly true on Windows: settings are written before data — §8 Q-10.)

**FLASH-048 — Re-entrancy guard.** `_applying` (volatile) is set before `FinishReceive` and cleared on every exit
path; while set, the capture callback returns immediately and a second completion cannot start another apply.

### 2.4 Wire protocol behaviours (user-invisible but contractual)

**FLASH-060 — Base45 (RFC 9285) text encoding** of every frame; invalid text is rejected (that is how foreign
QR codes are ignored). §3.1.

**FLASH-061 — CRC-32/ISO-HDLC** over the DEFLATE'd bytes, checked after reassembly, before inflate. §3.2.

**FLASH-062 — Raw DEFLATE (RFC 1951)** — no zlib/gzip wrapper; the inflater is told the exact raw length. §3.3.

**FLASH-063 — xorshift32 PRNG**, integer-only, zero seed remapped to `0x9E3779B9`. §3.4.

**FLASH-064 — Degree table** (coarsened Robust Soliton, integer CDF out of 1024). §3.5.

**FLASH-065 — Index derivation**: round-robin cycling for K ≤ 8; systematic prefix (seed < K → chunk `seed`);
otherwise PRNG-drawn sorted index set. §3.6.

**FLASH-066 — Frame format**: 5-byte header `41 41 51 01 {type}`; manifest (type 0) and data (type 1) frames,
big-endian; strict validation on decode. §3.7.

**FLASH-067 — Encoder**: chunkSize 900, K = ⌈coded/900⌉ (1…65535), last chunk zero-padded, manifest every 12th
emitted frame, **seed counter separate from emit counter**, endless. §3.8.

**FLASH-068 — Peeling decoder** with late join, session/CRC-change reset, duplicate-seed rejection. §3.9.

**FLASH-069 — Hostile-input hardening**: manifest with chunkSize 0 or chunkCount 0 rejected; unknown kind
rejected; `Finish()` never throws and caps allocations at 64 MiB. §3.9.

**FLASH-070 — Manifest label** ≤ 120 UTF-8 **bytes** (byte-truncated, may split a character; decoder replaces
invalid UTF-8 with U+FFFD). Windows labels: `full database` (snapshot) or the change-set summary.

**FLASH-071 — QR symbol requirements**: text in QR **alphanumeric mode**, ECC level **L** (minimum; Nayuki may
boost it when it fits in the same version), smallest version that fits, automatic mask, **4-module quiet zone**,
black on white, crisp nearest-neighbour modules. With chunkSize 900 a data frame is 911 bytes → 1367 Base45
characters → **version 22-L, 105 × 105 modules** (113 × 113 including the quiet zone). §3.10.

### 2.5 Change-set and snapshot semantics

**FLASH-080 — Structural diff of every top-level key** of `data.json` — no allowlist (`BuildChangeSet`). A
collection added by a future build of either app syncs without code changes. §3.11.

**FLASH-081 — Excluded data keys**: `LastModified` (re-stamped by the applier) and `Ui` (handled key-by-key,
FLASH-086) never travel as blocks and are never assigned wholesale on apply.

**FLASH-082 — Id collections diffed per item**: an array containing at least one object with a non-null `Id`
(in current *or* baseline) is diffed by `Id`: changed/new items travel **whole** in `Sets[name]`, removed ids in
`Deletes[name]`.

**FLASH-083 — Whole-array fallback**: if any element of the current array lacks an `Id` (or isn't an object), or
the current value is no longer an array, the whole value travels in `Blocks[name]`.

**FLASH-084 — Order only when needed**: `Order[name]` = the full current id sequence, sent only when upsert-in-
place + append + delete would not already reproduce it on the receiver.

**FLASH-085 — Blocks / BlockDeletes**: any other changed top-level key travels whole in `Blocks`; a key that
disappeared (absent **or JSON null** now, non-null before) is named in `BlockDeletes`.

**FLASH-086 — Ui merged key by key**: shared preferences diffed into `UiChanges` (changed/added keys, whole
values) and `UiDeletes` (removed keys); 16 **per-device** keys never travel and are never touched on apply.

**FLASH-087 — Settings**: `settings.json` minus 11 excluded keys is compared as a whole; when it differs the
**entire** stripped current settings object travels in `Settings`, plus `SettingsDeletes` = keys present
(non-null) in the stripped baseline but absent/null now. Applied by **merging**, never replacing.

**FLASH-088 — Change-set envelope**: `V` = 1, `From` = this install's identity (`DataStore.AppIdentity`),
`Created` = local time `yyyy-MM-ddTHH:mm:ss`; every section omitted when empty; `BuildChangeSet` returns null
(nothing to send) when every section is empty.

**FLASH-089 — Apply order**: Sets → Deletes → Order → Blocks (except excluded) → Ui merge (legacy `Blocks.Ui` +
`UiChanges`, then `UiDeletes`) → BlockDeletes → merge Settings → remove SettingsDeletes → stamp `LastModified`.

**FLASH-090 — Legacy senders**: an old iOS build ships the whole `Ui` under `Blocks.Ui`; it is folded into the
key-level merge (per-device keys stripped), never assigned.

**FLASH-091 — Snapshot envelope** `{"V":1,"Data":{…},"Settings":{…}}`; `Data` = data.json minus `LastModified`,
with `Ui` reduced to its shared preferences; `Settings` = settings minus excluded keys.

**FLASH-092 — Snapshot apply**: replaces the whole database; takes the sender's shared `Ui` preferences but keeps
this device's per-device `Ui` keys; merges settings; also accepts a **bare `data.json`** (no settings).

**FLASH-093 — Human summary** (label + review text), e.g. `2 Tasks, 1 deleted, Log, layout, settings`;
destructive operations are always named (`REMOVES …`, `clears N setting(s)`); never "no changes".

**FLASH-094 — Deep equality** used for every "changed?" decision: key-order-insensitive objects, ordered arrays,
scalars compared by their serialized JSON text (numbers by source lexeme, strings ordinally). §3.11.9.

**FLASH-095 — Zero-data-loss transport**: items are copied as JSON subtrees, never re-serialised through the typed
model on the way, so unmodelled keys, rich text (`RichTextXaml`), checklists, colours, schedules, attachment
metadata, `enc:` bodies etc. ride along untouched.

### 2.6 Baseline and store

**FLASH-100 — Baseline file** `qrsync-baseline.json` in the data folder:
`{"StampedUtc":"<ISO-8601 round-trip UTC>","Data":{full data tree},"Settings":{full settings tree}|null}`,
written atomically (`.tmp` + move/overwrite). §4.4.

**FLASH-101 — Baseline written at exactly two moments**: after the user confirms the peer received what was sent
(FLASH-020), and after this machine applies something it received (FLASH-105).

**FLASH-102 — Baseline read tolerance**: missing or unreadable baseline → "no baseline" → next send is a full
snapshot (never an error).

**FLASH-103 — Outgoing decision** (`BuildOutgoing`): baseline → change set (or null if unchanged) with label =
summary; no baseline → snapshot with label `full database`.

**FLASH-104 — Preview has no side effects**: decides snapshot vs change set and the summary without touching
anything; null when not a JSON object.

**FLASH-105 — Apply pipeline**: merge into settings tree → write settings.json → reload settings → hand the new
data tree to `DataStore.ApplySyncedData` (local encryption honoured, path migration, active data file reset to the
default `data.json`) → write the baseline from the result.

**FLASH-106 — Baseline reset API** (`ClearBaseline`, `HasBaseline`) exists but has **no UI** on Windows (deleting
the file by hand is the only recovery path). Mac: see FLASH-131.

**FLASH-107 — What never travels**: attachment bytes (`files/`), secrets (`GeminiApiKey`, OAuth tokens,
`PasswordHash`/`PasswordSalt`), machine-local absolute paths, per-install policy/identity settings, per-device
`Ui` keys, `LastModified`, the baseline file itself, crash artefacts, Folder-Builder output, OS permissions.

### 2.7 Conformance tooling

**FLASH-120 — Interop CLI** (`Tests/FlashSync.Interop`): `vectors`, `encode`, `decode`, `cs-build`, `cs-apply`,
`snap-build`, `snap-apply`, compiled from the app's own four WPF-free files (linked, not copied). §3.14.

**FLASH-121 — Frame-file format**: one Base45 frame string per line; the interop surface with the Swift (iOS)
twin. §4.6.

### 2.8 Mac additions (not in Windows; each is additive and optional unless marked)

**FLASH-130 — (recommended) Live theme after apply.** Windows merges an incoming `DarkMode` into settings.json
but only re-themes on next launch (and its Dark-mode menu check stays stale). The Mac should apply the merged
theme immediately.

**FLASH-131 — (optional) "Reset pairing…"** action (Send tab overflow menu) that calls `clearBaseline()` after a
confirmation, so the next send is a full snapshot — the recovery path the Windows class comments describe but
never expose.

**FLASH-132 — (spec-required, missing on Windows) Say when a snapshot carries no settings.** Protocol §10:
"Say so in the UI when settings are absent". When a snapshot is a bare `data.json` (or the envelope's `Settings`
is not an object), append to the review text: `This copy carries no settings (dark mode etc. stay as they are).`

**FLASH-133 — (optional) Receive from the screen** (ScreenCaptureKit) — e.g. from the **iPhone Mirroring** window
or any window/display region — instead of a camera. §6.4.4.

**FLASH-134 — (optional) Present the QR full-screen** on a chosen display (brightest / facing the phone).

**FLASH-135 — (optional) Rich review sheet**: per-collection breakdown (sets / deletes / blocks / removals in red
/ settings / layout) under the exact FLASH-044 summary line.

---

## 3. Logic and algorithms

All line numbers refer to `/Users/eriskay/erisdev/AA/AA/…` unless stated.

### 3.1 Base45 — `FlashSync/FlashSyncCodec.cs:15-75`

Alphabet (index 0…44), exactly: `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:` (digits, `A`–`Z`, **space**,
`$ % * + - . / :`). Reverse table covers code points 0…127; anything ≥ 128 is invalid.

* **Encode** (`:27-45`): for each byte pair `[a,b]`, `n = a*256 + b`; emit `A[n%45]`, `A[(n/45)%45]`,
  `A[n/45/45]`. A single trailing byte `a` emits `A[a%45]`, `A[a/45]`. Empty → `""`.
* **Decode** (`:49-72`) returns **nil** on any invalid input:
  * `length % 3 == 1` → nil (one trailing character is invalid);
  * each 3-char group: all chars in alphabet, `n = c0 + c1*45 + c2*2025` must be ≤ `0xFFFF` → bytes `n>>8`,
    `n&0xFF`;
  * a final 2-char group: `n = c0 + c1*45` must be ≤ `0xFF` → one byte.
* Swift notes: operate on `Array(string.utf8)` (all valid chars are ASCII, so any non-ASCII UTF-8 byte ≥ 0x80
  fails the lookup — equivalent to C#'s `c < 128` test on UTF-16). **Never trim** frame strings: space is a
  legal Base45 character and frames can start or end with it (vector in §7.1).

### 3.2 CRC-32 — `FlashSyncCodec.cs:78-99`

Table-driven, reflected, polynomial `0xEDB88320`, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF`
(`c = T[(c ^ b) & 0xFF] ^ (c >> 8)`). Identical to the ZIP CRC — the Mac should share one implementation with
the in-house ZIP writer (`AACore`), or use `zlib`'s `crc32` from libz (a system library, not a third-party
dependency). Output is a `UInt32`.

### 3.3 Raw DEFLATE — `FlashSyncCodec.cs:117-142`

* `Compress`: `DeflateStream(CompressionLevel.Optimal)` — raw RFC 1951, no header. Output of different encoders
  legally differs; only inflatability matters.
* `Inflate(coded, rawLength)`: allocate exactly `rawLength`, read until full or the stream ends; if fewer than
  `rawLength` bytes were produced → throws `InvalidDataException("Inflate produced {off} bytes, expected
  {rawLength}.")`. **Extra output beyond `rawLength` is silently ignored** (never read).
* Mac: Apple `Compression` with `COMPRESSION_ZLIB` is raw DEFLATE (verified: it reproduces the protocol's iOS
  vector `73748401273870860300` byte-for-byte and inflates it). Decode with
  `compression_decode_buffer(dst, rawBytes, src, n, nil, COMPRESSION_ZLIB)` and require the return value to equal
  `rawBytes` (a too-small destination returns the destination size, i.e. excess is ignored — same as .NET).
  Encode with the streaming API (`compression_stream` / `NSData.compressed(using: .zlib)`) or
  `compression_encode_buffer` with a destination of at least `n + n/1000 + 64` bytes — the buffer API returns 0
  when the destination is too small, which must be treated as an error, not as empty output. Empty input
  encodes to `03 00`.

### 3.4 xorshift32 — `FlashSyncCodec.cs:102-114`

```
state = (seed == 0) ? 0x9E3779B9 : seed
next(): s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s          // all UInt32, logical shifts
next(n): Int(next() % UInt32(n))
```
Swift: `UInt32` with plain `<<`/`>>` (Swift shifts discard overflowed bits and never trap; `>>` on `UInt32` is
logical). No floating point anywhere.

### 3.5 Degree — `FlashSyncCodec.cs:151-164`

CDF (threshold out of 1024 → degree): `(84,1) (554,2) (718,3) (800,4) (851,5) (882,6) (903,7) (918,8)
(942,12) (963,20) (1000,35) (1024,60)`. `x = r % 1024`; first entry with `x < threshold` → `min(degree, K)`;
fallback (unreachable) `min(2, K)`.

### 3.6 Indices — `FlashSyncCodec.cs:167-186`

```
CyclingThreshold = 8
indices(seed: UInt32, K: Int) -> [Int]:
  if K <= 0: return []
  if K <= 8: return [Int(seed % UInt32(K))]            // small payloads: round-robin, no mixing
  if seed < UInt32(K): return [Int(seed)]              // systematic prefix
  rng = QrRandom(seed)
  degree = Degree(rng.next(), K)                       // FIRST draw is the degree
  picked = sorted set; spins = 0
  while picked.count < degree && spins < degree*24:    // duplicates count as spins, collapse in the set
      picked.insert(rng.next(K)); spins += 1
  if picked.isEmpty: picked.insert(Int(seed % UInt32(K)))
  return picked ascending
```
The ten protocol rows (§7.3) must reproduce exactly before anything else is built.

### 3.7 Frames — `FlashSyncCodec.cs:189-298`

`FrameKind`: `ChangeSet = 0`, `FullSnapshot = 1`. All integers big-endian.

Header (5 bytes): `41 41 51` ("AAQ"), version `01`, type (`00` manifest, `01` data).

Manifest (type 0), 25 + n bytes:

| off | size | field |
|---|---|---|
| 5 | 2 | session (u16) |
| 7 | 4 | codedBytes (u32) — DEFLATE'd length |
| 11 | 4 | rawBytes (u32) — original length |
| 15 | 2 | chunkSize (u16) |
| 17 | 2 | chunkCount K (u16) |
| 19 | 4 | crc32 (u32) of the coded bytes |
| 23 | 1 | kind (0/1) |
| 24 | 1 | labelLen (≤ 120) |
| 25 | n | label, UTF-8 |

Data (type 1): session u16 @5, seed u32 @7, payload @11 (exactly chunkSize bytes when valid).

`EncodeManifest` (`:218-234`): label = UTF-8 bytes of `Label`, **truncated to the first 120 bytes** if longer
(may cut a multi-byte character). `EncodeData` (`:236-244`): header + session + seed + payload.

`Decode(bytes)` (`:248-292`) → manifest | data | nil:
1. `len < 5` → nil; bytes 0…3 ≠ `41 41 51 01` → nil.
2. type 0: `len < 25` → nil; `chunkSize == 0 || chunkCount == 0` → nil (a K=0 manifest would otherwise
   report a completed transfer before any data); `kind > 1` → nil; `len < 25 + labelLen` → nil; label decoded as
   UTF-8 with replacement (U+FFFD) of invalid sequences; **trailing bytes after the label are ignored**.
3. type 1: `len <= 11` → nil (at least one payload byte); payload = bytes 11…end (any length; the decoder
   checks it against chunkSize).
4. any other type → nil. Any exception → nil.

### 3.8 Encoder — `FlashSync/FlashSyncEncoder.cs`

Constructor (`:22-48`), `(payload, kind, label, session, chunkSize = 900)`:
* `coded = Deflate.Compress(payload)`; `K = max(1, ⌈coded.count / chunkSize⌉)`; `K > 65535` → throw
  `InvalidOperationException("Payload too large for Flash Sync: {K} chunks (max 65535).")`.
* `chunks[i]` = `coded[i*chunkSize ..< min((i+1)*chunkSize, count)]` zero-padded to `chunkSize`.
* Manifest: `{session, codedBytes = coded.count, rawBytes = payload.count, chunkSize, chunkCount = K,
  crc32 = CRC(coded), kind, label}`.

`Next()` (`:52-70`), returns the Base45 string for the next QR:
```
if emitted % 12 == 0 { emitted += 1; return base45(encodeManifest(manifest)) }
emitted += 1
s = seed; seed += 1                      // SEPARATE counter: manifests never consume a seed
idx = indices(s, K)
body = copy(chunks[idx[0]]); for k in idx[1...]: body ^= chunks[k]   (byte-wise over chunkSize)
return base45(encodeData(session, s, body))
```
Emission order: `M, 0,1,…,10, M, 11,…,21, M, 22,…` (§7.5). Separating the counters is what makes a clean capture
cost exactly K data frames (1.00×); letting the manifest consume seeds made chunks 0, 12, 24… never systematic
(an iOS bug, fixed). Use wrapping `&+=` for both counters in Swift (never reached in practice).

`NewSession()` (`:72`): `Random.Shared.Next(1, 65536)` → 1…65535. Swift: `UInt16.random(in: 1...65535)`.

### 3.9 Decoder — `FlashSync/FlashSyncDecoder.cs`

State: `manifest?`, `solved: [Int: [UInt8]]`, `pending: [Equation(idx: Set<Int>, body: [UInt8])]`,
`seenSeeds: Set<UInt32>`. Properties: `SolvedCount`, `ChunkCount` (= manifest K or 0), `IsComplete`
(`manifest != nil && solved.count == K`), `Label` (manifest label or `""`), `Manifest`.

`Ingest(text)` (`:34-64`):
1. `Base45.Decode` → nil → return. `FlashFrame.Decode` → nil → return.
2. Manifest: no manifest yet → adopt, return. Else if `session` **or** `crc32` differs → **Reset** (clear
   solved, pending, seenSeeds) and adopt the new one. Otherwise ignore it (a later manifest with the same
   session+CRC never replaces the first, even if other fields differ). Return.
3. Data: ignore if no manifest yet (frames seen before the first manifest are **not buffered**; the manifest
   recurs every 12 frames so at most 11 are lost), if `session` differs, if `payload.count != chunkSize`, or if
   the seed was already seen (`seenSeeds.insert` fails).
4. `idx = Set(indices(seed, K))`; `body = copy(payload)`; for every k in idx already solved: `body ^= solved[k]`,
   remove k.
5. `idx` empty → redundant, drop. One left → `Solve(k, body)`. Else append to pending.

`Solve(index, value)` (`:66-90`): LIFO stack; pop `(i, v)`; skip if solved; `solved[i] = v`; rebuild pending:
each equation containing i gets `body ^= v`, `idx.remove(i)`; if it becomes empty → drop; if one index left →
push `(thatIndex, body)` and drop the equation; else keep. Iterate until the stack is empty.

`Finish()` (`:94-120`) → payload or nil, **never throws** (runs at the moment the user applies; every field came
off a camera):
1. not complete → nil.
2. `total = K * chunkSize` (64-bit); `total <= 0 || total > 64 MiB (67 108 864)` → nil.
3. concatenate `solved[0..<K]`; any missing chunk or chunk length ≠ chunkSize → nil.
4. `codedBytes <= 0 || codedBytes > total` → nil; truncate to `codedBytes`.
5. `CRC32(coded) != manifest.crc32` → nil ("corrupted — report, change nothing").
6. `rawBytes <= 0 || rawBytes > 64 MiB` → nil (so an empty payload can never be transferred).
7. `Inflate(coded, rawBytes)`; any error → nil.

`Reset()` clears solved/pending/seenSeeds (not the manifest; the caller replaces it). A **new decoder** is created
for every "Start camera".

Performance: pending is scanned once per solved chunk (fine up to K≈1000; the interop stress test used K≈950).
Swift: implement `xor` over `UnsafeMutableRawBufferPointer` in 8-byte words (900 bytes = 112 words + 4 bytes);
confine the decoder to the capture queue (it is not thread-safe).

### 3.10 QR generation and raster — `FlashSync/FlashQr.cs`

* `Generate(base45)` (`:17`): `QrCode.EncodeText(text, Ecc.Low)` from **Net.Codecrete.QrCodeGenerator 2.0.6**
  (a port of **Nayuki's** reference QR library). `EncodeText` = `MakeSegments(text)` (numeric if all digits;
  **alphanumeric** if every char is in `0-9A-Z $%*+-./:`; otherwise UTF-8 bytes) →
  `EncodeSegments(segs, ecl: Low, minVersion 1, maxVersion 40, mask -1 (auto), boostEcl: true)`.
  Base45 frames always start `AB8$AA` (never all-numeric) and are always alphanumeric.
* Why not QRCoder (removed): its Reed-Solomon long division terminates early when a block's data begins with ≥
  `eccPerBlock` zero codewords and emits **all-zero ECC** — exactly what the zero-padded tail chunk produces; the
  symbol is unreadable by ZBar, OpenCV and Apple Vision, and at K ≤ 8 that frame travels alone → an ordinary small
  edit would hang forever. Any Mac generator **must** be tested against this case (§7.9).
* Why not ZXing for reading: its detector misses **mask-0** symbols even when clean, and zero-padded frames
  naturally select mask 0.
* `RenderBgra(qr, scale, out size)` (`:22-45`): `scale < 1 → 1`; border 4 modules; `size = (qrSize + 8) *
  scale`; white BGRA field; dark modules → `B=G=R=0`, alpha stays 255. `ToBitmapSource(string)` renders at
  scale 1 and relies on the Image's nearest-neighbour up-scaling (`:58-62`).
* Symbol sizes (computed from the QR capacity tables with Nayuki's selection rules):

| frame | bytes | Base45 chars | alphanumeric (what Windows/Nayuki produce) | same text forced to byte mode |
|---|---|---|---|---|
| data frame, chunkSize 900 | 911 | 1367 | **v22-L, 105 modules** | v26-L, 121 modules |
| manifest, empty label | 25 | 38 | v2-M (boosted), 25 modules | v3-M |
| manifest, `full database` | 38 | 57 | v3-M (boosted), 29 modules | v4-M |
| manifest, 120-byte label | 145 | 218 | v7-L, 45 modules | v9-L |

  (The protocol text says "around version 20"; the real figure is 22 — the camera comment in `FlashCamera.cs`
  says 22.)

### 3.11 Change sets — `FlashSync/FlashChangeSet.cs`

All functions are pure over `JsonNode` trees (System.Text.Json.Nodes). The Mac port must operate on the AACore
ordered `JSONValue` tree with the **same accessor semantics** (§3.11.10).

#### 3.11.1 Constant sets (`:18-56`) — must be byte-identical on every platform

* `ExcludedDataKeys` = `{"LastModified", "Ui"}` (ordinal).
* `PerDeviceUiKeys` (16, ordinal; identical to `rSyncPerDeviceUiKeys` in the iOS repo):
  `WindowLeft, WindowTop, WindowWidth, WindowHeight, WindowState, DueWindowWidth, DueWindowHeight,
  SelectedMainTabIndex, SelectedEquipmentId, SelectedTaskId, SelectedProcedureId, SelectedVesselId,
  CalendarSelectedDate, MapFocusedItemId, GroupExpanded, LastDigestDate`. A **denylist** on purpose (an allowlist
  would silently stop every new preference from syncing).
* `ExcludedSettingsKeys` (11): `GeminiApiKey, CurrentDataFile, GoogleDriveFolder, FolderBuilderBase,
  SharedSaveFile, PasswordHash, PasswordSalt, EncryptLocalData, AppIdentity, SyncOnSave, TextOnlyExport`.

#### 3.11.2 `BuildSnapshot(data, settings)` (`:61-92`)

Returns a new object, keys in this order: `"V": 1`, `"Data": StripExcludedData(data)`,
`"Settings": StripExcludedSettings(settings)` (JSON `null` if settings is nil — never the case from the store,
which always passes an object).
`StripExcludedData`: copy every key of `data` in order except `LastModified` and `Ui`; then, **if `data.Ui` is an
object**, append `"Ui": SharedUi(ui)` (all keys except the 16 per-device ones, in order). So in the envelope `Ui`
moves to the **end** of `Data`.

#### 3.11.3 `IsSnapshotEnvelope(node)` (`:95-96`)

True iff `node` is an object, `node["V"]` is non-null (present and not JSON null) and `node["Data"]` is an
**object**. `data.json` has no top-level `Data`, so the test is unambiguous.

#### 3.11.4 `BuildChangeSet(current, baselineData?, currentSettings?, baselineSettings?, from, createdLocal)` (`:102-187`)

```
for name in UnionKeys(current, baselineData):        // current's keys in order, then baseline-only keys
    if name in ExcludedDataKeys: continue
    c = current[name]; b = baselineData?[name]       // nil = absent OR JSON null
    if DeepEquals(c, b): continue
    if c == nil: BlockDeletes.append(name); continue
    isColl = IsIdCollection(c) || IsIdCollection(b)  // array with ≥1 object whose "Id" is non-null
    if !isColl: Blocks[name] = clone(c); continue
    if c is not an array || any element is not an object or has a nil "Id":
        Blocks[name] = clone(c); continue            // can't address items → whole array/value
    (bIds, bMap) = OrderedIds(b as? array)           // ids as strings, first occurrence wins
    (cIds, cMap) = OrderedIds(c)
    itemSets = [clone(cMap[id]) for id in cIds if bMap[id] == nil || !DeepEquals(cMap[id], bMap[id])]
    if !itemSets.isEmpty: Sets[name] = itemSets      // in CURRENT order
    dels = [id for id in bIds if cMap[id] == nil]    // in BASELINE order, as JSON strings
    if !dels.isEmpty: Deletes[name] = dels
    predicted = bIds minus dels; then append each cId not already in predicted
    if predicted != cIds: Order[name] = cIds         // array of JSON strings
(settingsOut, settingsDeletes) = DiffSettings(currentSettings, baselineSettings)
UiChanges: for (k, v) in current.Ui (if object): if k not per-device && !DeepEquals(v, baselineUi?[k]): UiChanges[k] = clone(v)
UiDeletes: for k in baselineUi (if object): if k not per-device && (currentUi == nil || !currentUi.containsKey(k)): append k
if everything empty (and settingsOut == nil): return nil
result keys in order: V=1, From=from, Created=createdLocal "yyyy-MM-ddTHH:mm:ss",
   then (each only if non-empty) Sets, Deletes, Blocks, BlockDeletes, Order,
   Settings (if settingsOut != nil — even when it is {}), SettingsDeletes, UiChanges, UiDeletes
```
Notes and edge cases:
* A top-level key whose value is JSON `null` now but non-null in the baseline is a **BlockDelete** (null ≡ absent).
  Null in both, or absent in one and null in the other, is "unchanged".
* Collections with duplicate ids: only the first occurrence of each id participates; duplicates are neither sent
  nor deleted explicitly.
* `Sets` items are whole objects; no field-level patches.
* `UiChanges` values may be JSON `null` if a current Ui key is present with value null and the baseline has a
  non-null value for it. Current-null vs baseline-absent is "unchanged".
* A current `Ui` key present but `current.Ui` not an object → no UiChanges; baseline shared keys → UiDeletes.
* Ids are compared as strings via `JsonNode.ToString()` (§3.11.10): a string id is its raw value; a number id is
  its lexeme. App ids are GUID strings (lowercase `D` format).
* A change set carrying only `Order` summarises as `other changes` (Summarize does not name Order).

#### 3.11.5 `DiffSettings(current?, baseline?)` (`:189-198`)

`cur = StripExcludedSettings(current) ?? {}`, `bas = StripExcludedSettings(baseline) ?? {}`. If
`DeepEquals(cur, bas)` → `(nil, [])`. Else `deletes` = for name in UnionKeys(bas, cur): `bas[name] != nil &&
cur[name] == nil` (baseline order), and `settingsOut = cur` (the **whole** stripped current settings object,
not only the changed keys — may be `{}`).

#### 3.11.6 `ApplyChangeSet(changeSet, data, settings, nowLocal)` (`:203-284`) — mutates in place

1. **Sets** (object): for each `(name, arr)` where `arr` is an array: `target = data[name] as? array`; if not an
   array (absent, null, object…) → a **new empty array is assigned** to `data[name]` (replacing whatever was
   there). For each item that is an object: `id = item["Id"]?.toString()`; `IndexOfId(target, id)` (first element
   whose non-null `Id` string equals id; nil id → −1); found → replace in place with a clone; else append a clone.
2. **Deletes** (object): for each `(name, ids)` where `data[name]` is an array and `ids` an array: `idSet` =
   `ids.map { $0?.toString() ?? "" }`; remove (back-to-front) **every** element whose non-null `Id` string is in
   idSet (duplicates included).
3. **Order** (object): for each `(name, ids)` where `data[name]` is an array and `ids` an array → `Reorder`.
4. **Blocks** (object): for each `(name, val)`, if `name` not in ExcludedDataKeys → `data[name] = clone(val)`
   (JSON null value → the key is set to null, not removed; existing key keeps its position, new key appended).
5. **Ui**: `uiIn` = (if `Blocks.Ui` is an object) its entries, then `UiChanges` entries overwrite (later wins);
   `uiDel = UiDeletes as? array`. If `uiIn` non-empty or `uiDel` non-empty: ensure `data.Ui` is an object (else
   assign a new `{}`), then for each `(k,v)` in uiIn with k not per-device: `Ui[k] = clone(v)`; for each entry of
   uiDel (`toString() ?? ""`) not per-device: remove it.
6. **BlockDeletes** (array): remove each named key (`toString() ?? ""`) from `data` — **no exclusion check**.
7. **Settings** (object): merge each `(k,v)` with k not excluded: `settings[k] = clone(v)`.
8. **SettingsDeletes** (array): remove each named key from settings — **no exclusion check** (§8 Q-2).
9. `data["LastModified"] = nowLocal` formatted `yyyy-MM-ddTHH:mm:ss.fffffff` (7 fractional digits, local wall
   time, **no offset**).

`Reorder(target, orderIds)` (`:397-420`): `byId` = first element per non-null id; `rebuilt` = for each id in
orderIds (in order): if present and not yet used → append; then every original element in original order
**except** elements whose id is in `used`. Results: unnamed ids keep relative order after the named ones;
**id-less elements are moved after all named elements** (not kept in place, despite the code comment); a
**second element with an already-placed id is dropped**; named-but-absent ids are skipped. Everything is cloned.

#### 3.11.7 `ApplySnapshot(payload, settings, nowLocal, out hadSettings, existingData?)` (`:291-323`)

```
if IsSnapshotEnvelope(payload):
    data = clone(payload.Data)
    if payload.Settings is object: hadSettings = true; merge non-excluded keys into settings
else: data = clone(payload)                                   // bare data.json, no settings
incomingUi = data["Ui"] as? object
data.remove("LastModified"); data.remove("Ui")
mergedUi = incomingUi != nil ? SharedUi(incomingUi) : {}
if existingData?.Ui is object: for (k,v) in it where k IS per-device: mergedUi[k] = clone(v)
if incomingUi != nil || existingData?["Ui"] != nil: data["Ui"] = mergedUi     // appended at the end
if existingData != nil: data["LastModified"] = existingData.LastModified (if non-null)  // then overwritten:
data["LastModified"] = nowLocal "yyyy-MM-ddTHH:mm:ss.fffffff"                 // appended at the end
return data
```
Consequences: the receiver's **shared** Ui preferences are replaced by the sender's (a local shared key the sender
lacks is dropped); the receiver's per-device keys survive; settings keys the sender lacks survive (merge only; no
deletes on a snapshot). `hadSettings` is computed but ignored by `FlashSyncStore.Apply` (see FLASH-132).

#### 3.11.8 `Summarize(changeSet)` (`:327-352`)

Parts, in this order, joined by `", "`:
1. for each `Sets` entry whose value is a non-empty array: `"{count} {name}"` (raw collection name, e.g.
   `2 Tasks`, `1 Equipment`);
2. total count over all `Deletes` arrays > 0: `"{n} deleted"`;
3. `Blocks` non-empty: its key names joined by `", "` (so a legacy `Blocks.Ui` shows as `Ui`);
4. `UiChanges` non-empty **or** `UiDeletes` non-empty: `layout`;
5. `BlockDeletes` non-empty: `"REMOVES " + names joined ", "` (a null entry shows as `?`);
6. `Settings` present (any non-null value): `settings`;
7. `SettingsDeletes` non-empty: `"clears {n} setting"` + `s` unless n == 1.
No parts → `other changes` (a built change set always changes something; never claim "no changes").

#### 3.11.9 `DeepEquals(a, b)` (`:422-444`)

* both nil → true; one nil → false (nil = absent or JSON null).
* objects: equal **count** (null-valued properties count) and every key of `a` present in `b`
  (`TryGetPropertyValue`, ordinal) with deep-equal values — **key order ignored**.
* arrays: equal length and element-wise deep-equal (order matters).
* scalars: `a.ToJsonString() == b.ToJsonString()`:
  * **numbers compare by source lexeme**: `1` ≠ `1.0` ≠ `1e0`, `-0` ≠ `0`;
  * **strings compare by value, ordinally** (UTF-16 code units; escaping normalised — `"é"` equals `"\u00e9"`,
    but precomposed `é` ≠ decomposed `e`+U+0301);
  * `true`/`false` by value; a string never equals a number (`"1"` ≠ `1`).
* object vs array vs scalar → false.

Swift pitfall: `String ==` and `Dictionary<String,…>` use **Unicode canonical equivalence**; .NET uses ordinal.
Compare/hash keys and string values by their UTF-8 (or UTF-16) code units.

#### 3.11.10 Required `JSONValue` accessor semantics (to mirror `JsonNode`)

| C# idiom | meaning to replicate |
|---|---|
| `obj[key]` | nil when the key is absent **or** its value is JSON null |
| `obj[key] = v` | replace in place (position kept) if present, else append at the end |
| `obj.Remove(k)` | remove; later re-add appends at the end |
| `obj.ContainsKey(k)` / `TryGetPropertyValue` | true for a key whose value is JSON null |
| `node.ToString()` for ids | string → raw value; number → lexeme; bool → `true`/`false`; (object/array → JSON text, unused) |
| `ToJsonString()` | compact JSON, default System.Text.Json escaping (non-ASCII and `< > & ' + \`` as `\uXXXX`, uppercase hex) |
| `JsonNode.Parse` | objects preserve key order; numbers keep their lexeme; keys case-sensitive |

### 3.12 Store — `FlashSync/FlashSyncStore.cs`

* `BaselinePath` (`:21`) = `<AppFolder>/qrsync-baseline.json` (`AppFolder` honours `AA_DATA_DIR`).
* `ReadDataTree()` (`:26-27`) = `JsonNode.Parse(DataStore.SerializeForSave(DataStore.Load()))` — the database
  **read from disk** (current data file, decrypted if encrypted at rest), paths normalised, `SchemaVersion`
  stamped: "exactly as it would be written to disk". `ReadDataTree(AppData)` (`:30-31`) does the same for a model
  in hand. Side effect on Windows: `Load()` resets `DataStore.LastLoadFailed`. **An unreadable data file loads as
  an empty database** (see §8 Q-5).
* `ReadSettingsTree()` (`:34-43`): parse `settings.json`; missing/unreadable/non-object → `{}`.
* `ReadBaseline()` (`:49-58`): missing → `(nil,nil)`; parse root; `Data`/`Settings` via `AsObject()` (a non-object
  throws → caught → `(nil,nil)`); `Settings` JSON null → nil.
* `WriteBaseline(data, settings?)` (`:62-78`): create folder; root `{"StampedUtc": DateTime.UtcNow.ToString("O"),
  "Data": clone(data), "Settings": clone(settings) | null}`; write compact to `qrsync-baseline.json.tmp`, then
  `File.Move(tmp, path, overwrite: true)` (atomic — a torn baseline would resend forever); all errors swallowed
  (worst case the next sync is a snapshot).
* `ClearBaseline()` (`:82-85`) deletes the file (errors swallowed); `HasBaseline` (`:87`) = file exists. Neither
  is called by any UI.
* `BuildOutgoing(from)` (`:93-108`): read data, settings, baseline. Baseline data non-nil → `BuildChangeSet(data,
  baseData, settings, baseSettings, from, DateTime.Now)`; nil → return nil ("nothing changed since they last
  confirmed"); else `(UTF8(cs.ToJsonString()), .changeSet, Summarize(cs))`. No baseline →
  `(UTF8(BuildSnapshot(data, settings).ToJsonString()), .fullSnapshot, "full database")`.
* `Preview(payload, kind)` (`:114-129`): `JsonNode.Parse(UTF8 decode)`; non-object → nil; `isSnapshot = kind ==
  .fullSnapshot || IsSnapshotEnvelope(obj)`; summary = `the sender's entire database (replaces yours)` for a
  snapshot else `Summarize(obj)`; any exception → nil. Pure.
* `Apply(change)` (`:134-156`):
  1. `settings = ReadSettingsTree()`;
  2. snapshot → `ApplySnapshot(payload, settings, DateTime.Now, out _, existingData: ReadDataTree())`; change set
     → `applied = ReadDataTree()` then `ApplyChangeSet(payload, applied, settings, DateTime.Now)`;
  3. `WriteSettingsTree(settings)` → write `settings.json` compact (errors swallowed) → `DataStore.LoadSettings()`;
  4. `data = DataStore.ApplySyncedData(applied.ToJsonString())` (`DataStore.cs:912-921`): **set the active data
     file to the default `<AppFolder>/data.json`**, write the JSON there (local at-rest encryption honoured),
     re-load it through the typed model (`LoadFrom`: tolerant, schema migration, path normalisation), migrate
     legacy absolute attachment paths (`…/files/x` → `files/x`), write it again via `SerializeForSave`, then
     `WriteSettings()` (re-serialises the settings DTO: known keys + preserved unknown `ExtraData`, persisting
     `CurrentDataFile` = default). Never touches `files/` — incoming items may reference attachments this machine
     lacks (they show as missing until a full bundle sync).
  5. `WriteBaseline(ReadDataTree(data), ReadSettingsTree())` — the receiver now agrees with the sender.
  6. return the model.
* `IncomingChange` (`:170-175`): `{Payload: JsonObject, IsSnapshot: Bool, Summary: String}`.

### 3.13 Windows capture / detection (to be replaced on the Mac)

* `FlashCamera.Enumerate(maxProbe = 5)` (`FlashCamera.cs:25-41`): open `VideoCapture(i, DSHOW)` for i in 0…4,
  keep those that open, release each probe.
* `FlashCamera.Start(index, onFrame, onError)` (`:48-78`): stop any previous; open; set width 1920, height 1080,
  fps 30, buffer size 1 (ignore failures); start background thread.
* `Loop` (`:80-100`): read frame; empty/failed read → `emptyRun += 1`, >120 → error "The camera stopped sending
  frames.", sleep 10 ms; else reset counter and call `onFrame(frame)` (same `Mat` reused — consumers must not keep
  it). Exceptions → "Camera error: …".
* `Stop()` (`:102-110`): flag off, join ≤ 500 ms, release/dispose.
* `FlashQrDecoder` (`FlashQrDecoder.cs`): OpenCV **WeChat** CNN QR detector (detect + super-resolution Caffe models,
  ~1 MB, embedded resources `AA.FlashSync.Models.{detect.prototxt, detect.caffemodel, sr.prototxt,
  sr.caffemodel}`), unpacked once to `<AppFolder>/qrmodels/` (re-extracted if a file is missing or its length
  differs; missing resource → `Embedded QR model '{name}' is missing from the build.`). `Decode(Mat)`: convert to
  gray (BGR/BGRA/gray), `DetectAndDecode`, return all strings; never throws (empty array). Measured: 95.5 %
  overall, 82 % under blur + warp + glare vs 42 % for managed decoders, zero wrong decodes in ~5 000 trials,
  ~15 ms/frame.
* `OnCameraFrame` (`FlashSyncWindow.xaml.cs:228-267`, capture thread): skip if applying; decode; if ≥100 ms since
  the last preview push, convert the frame to a frozen BGRA bitmap; ingest every string; snapshot (complete,
  solved, total, label); `BeginInvoke` the UI update and the completion trigger.

### 3.14 Interop CLI — `Tests/FlashSync.Interop/Program.cs`

`net10.0` console app, `InvariantGlobalization=true`, linking `FlashSyncCodec.cs`, `FlashSyncEncoder.cs`,
`FlashSyncDecoder.cs`, `FlashChangeSet.cs`. Exit codes: 0 ok, 1 failure (`FAIL: …` on stderr), 2 usage
(`usage: vectors | encode | decode | cs-build | cs-apply` — the usage line omits the two snapshot commands).

| command | behaviour |
|---|---|
| `vectors` | Runs every protocol vector (Base45 ×6 + foreign-text rejection, CRC ×3, xorshift ×3 seeds, degree ×8, indices ×10, frame bytes/text ×4, DEFLATE ×2); prints `✓`/`✗` lines, then `ALL VECTORS PASS` or `{n} VECTOR(S) FAILED`. |
| `encode <payload> <out.frames> <n> <kind> <label> [session]` | kind `snapshot` → FullSnapshot, anything else → ChangeSet; session decimal u16 (random if omitted); writes n `Next()` strings, one per line; prints `C# encoded {n} frames, K={K}, raw={bytes}`. |
| `decode <in.frames> <out.payload>` | ingests lines until complete; incomplete → `FAIL: C# decoder incomplete after {lines} frames ({solved}/{K})`; CRC/inflate failure → `FAIL: C# decoder: CRC or inflate failed`; else writes bytes, prints `C# decoded {bytes} bytes after {lines} frames, label="{label}"`. |
| `cs-build <current> <baseline> <cur-settings> <base-settings> <out>` | `from = "Windows"`, created = 2026-09-27 12:00:00; writes the change set or `{}` when null; prints `C# built change set: {summary | no changes}`. |
| `cs-apply <data> <settings> <changeset> <out-data> <out-settings>` | now = 2026-09-27 12:00:00; prints `C# applied change set`. |
| `snap-build <data> <settings> <out>` | prints `C# built snapshot`. |
| `snap-apply <payload> <existing-data> <settings> <out-data> <out-settings>` | prints `C# applied snapshot (carried settings: True|False)`. |

A missing input file or a non-object file is treated as `{}`. Outputs are compact `ToJsonString()`.

---

## 4. Data formats

### 4.1 Wire bytes

See §3.7. Magic `AAQ`, version `0x01`. **Any change to framing, PRNG, degree table, index derivation or
compression is a new version number** — never a tweak. Frames that don't start `41 41 51 01` are ignored silently.

### 4.2 Payload JSON (after inflate)

UTF-8, **no BOM**, compact. Windows writes it with `JsonNode.ToJsonString()` default options (pure ASCII:
non-ASCII and HTML-sensitive characters escaped). A Mac writer using the AACore .NET-compatible writer produces
byte-identical payloads for identical trees; any other valid JSON is also accepted by all readers. Receivers
**should** tolerate a leading BOM.

**Change set (kind 0)** — keys in this order, each section omitted when empty (but `Settings` is present, possibly
`{}`, whenever settings changed):

| key | type | content |
|---|---|---|
| `V` | number | `1` |
| `From` | string | sender identity: Windows = `DataStore.AppIdentity` (editable, defaults to the machine name); iOS = `"iOS"`; interop CLI = `"Windows"`. Informational only — no receiver reads it. Mac: its `AppIdentity`. |
| `Created` | string | sender **local** time `yyyy-MM-ddTHH:mm:ss`, no offset, Gregorian, invariant digits |
| `Sets` | object | collection name → array of whole item objects |
| `Deletes` | object | collection name → array of id **strings** |
| `Blocks` | object | top-level key → whole value |
| `BlockDeletes` | array | top-level keys removed |
| `Order` | object | collection name → array of id strings (complete current order) |
| `Settings` | object | whole stripped settings |
| `SettingsDeletes` | array | settings keys removed |
| `UiChanges` | object | shared Ui key → whole value |
| `UiDeletes` | array | shared Ui keys removed |

(The protocol's jsonc example predates `UiChanges`/`UiDeletes` in its listing but its text defines them.)

**Snapshot (kind 1)**: `{"V":1,"Data":{…},"Settings":{…}}` (§3.11.2). Readers also accept a bare `data.json`
(no `V`+object `Data`).

### 4.3 Classification of today's data.json top-level keys (Windows `AppData`, PascalCase, nulls omitted)

| key | shape | Flash Sync treatment |
|---|---|---|
| `Equipment`, `Tasks`, `Procedures`, `Vessels` | arrays of `HierarchyItem` (Guid `Id`) | per-item Sets/Deletes/Order |
| `Groups` (`ItemGroup`), `Crew` (`CrewMember`), `ChecklistTemplates`, `ListGroups`, `QuickBuckets`, `Ports`, `ScheduleTemplates`, `Trash` (`TrashedItem`) | arrays of objects with Guid `Id` | per-item |
| `Log` | array of `LogEntry` (no `Id`) | whole-array `Blocks.Log` |
| `Sire` | object (`QuestionStatuses`, `Bookmarks`, `ForExport`, `Tasks`, `QuestionBodies`) | whole `Blocks.Sire` |
| `SchemaVersion` | number | `Blocks.SchemaVersion` when it differs |
| `Ui` | object (`UiState` + unknown members) | key-level merge (FLASH-086) |
| `LastModified` | string (DateTime) | excluded; re-stamped |
| any unknown key (`ExtraData`) | anything | classified structurally |

Shared `Ui` keys that travel today: `CalendarViewMode`, `CalendarFontScale`, `ShowShortcutBar`, `QuickViewPinIds`,
`TabColors`, `TabOrder`, `SortAZ`, `CrewSortMode`, `CrewTableColumns`, `CrewTableShownColumns`,
`CrewTableDateFormat`, `CrewTableDateSeparator`, plus any unknown Ui member. Per-device: the 16 keys of §3.11.1.

Settings keys (Windows DTO, PascalCase, nulls omitted, bools always written): `CurrentDataFile`, `PasswordHash`,
`PasswordSalt`, `GoogleDriveFolder`, `SyncOnSave`, `DarkMode`, `FolderBuilderBase`, `SharedSaveFile`,
`EncryptLocalData`, `GeminiApiKey`, `AppIdentity`, `TextOnlyExport` + unknown members preserved via
`[JsonExtensionData]`. **Only `DarkMode` and unknown keys travel.**

### 4.4 `qrsync-baseline.json`

Location: `<AppFolder>/qrsync-baseline.json` (Mac: `~/Library/Application Support/AA/qrsync-baseline.json`, or
under `AA_DATA_DIR`). Compact JSON: `{"StampedUtc":"2026-09-29T12:34:56.1234567Z","Data":{…},"Settings":{…}}`.
`StampedUtc` = .NET round-trip `"O"` format of UTC now (always 7 fractional digits + `Z`); informational (never
read). `Data` = full data tree (unstripped); `Settings` = full settings tree or `null`. Per-device by definition —
never exported, never synced, never bundled (`ExportFolderToZip` only stages `data.json`, `files/`,
`source.json`). `ImportFolderFromZip` wipes every file in AppFolder, including the baseline → the next Flash Sync
is a snapshot. Plaintext on Windows even when `EncryptLocalData` is on (§8 Q-11).

### 4.5 Timestamps written by Flash Sync

| where | format | zone |
|---|---|---|
| change set `Created` | `yyyy-MM-ddTHH:mm:ss` | local, no offset |
| `LastModified` written by the appliers | `yyyy-MM-ddTHH:mm:ss.fffffff` (7 digits) | local, no offset |
| baseline `StampedUtc` | `yyyy-MM-ddTHH:mm:ss.fffffffZ` | UTC |

After `ApplySyncedData` re-serialises through the model, `LastModified` becomes a `DateTime` of **Unspecified**
kind and is written by System.Text.Json **without offset and with trailing fractional zeros trimmed** (e.g.
`2026-09-27T12:00:00`), unlike a normal user save which writes a Local-kind value with `+hh:mm`. The Mac persistence
layer must read both and reproduce the same Kind semantics. Windows formats with the current culture (a culture
whose time separator isn't `:` or whose calendar isn't Gregorian would corrupt these strings); the Mac must always
use `en_US_POSIX` + Gregorian.

### 4.6 Interop frame file

One frame string per line (Windows writes CRLF on Windows, LF elsewhere; readers accept both). Only strip the line
terminator — **never trim spaces** (Base45 contains space). Empty lines are harmless (rejected by Base45: length 0
is valid Base45 but decodes to zero bytes → frame decode rejects `< 5` bytes).

### 4.7 Cross-version / cross-platform compatibility rules

1. Wire protocol v1 is frozen (magic, framing, PRNG, degree table, indices, raw DEFLATE, CRC, Base45).
2. The three key sets (§3.11.1) must be identical on Windows, iOS and Mac.
3. The Mac diffs the tree **its own serializer writes** — so its serializer must be idempotent
   (`write(read(write(x))) == write(x)`), or every sync will carry spurious changes.
4. GUIDs are written **lowercase** (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) — ids are matched ordinally as
   strings across devices; an uppercase `UUID().uuidString` would create duplicates on the other side.
5. Mac-only preferences and per-device state must **not** be stored in `settings.json` or `data.json.Ui` (use
   `UserDefaults` / window-frame autosave), or they would travel via `Settings`/`UiChanges` (Windows/iOS don't
   exclude them). If the Mac ever must add a per-device Ui or settings key, add it to all three platforms' sets.
6. Nested unknown members survive the wire but **not** a Windows apply (Windows preserves unknown members only on
   `AppData`, `UiState` and settings) — the Mac must not rely on inventing nested keys.
7. Rich text travels as the item's `RichTextXaml` string (WPF XAML `Section` markup) verbatim; Flash Sync never
   parses it. Encrypted container bodies (`enc:` …), per-item lock hashes and attachment metadata likewise ride as
   opaque strings. No XAML shapes are produced or consumed by this subsystem.

---

## 5. Dependencies

### 5.1 Called by

* `MainWindow.MenuFlashSync_Click` (opens the window; subscribes `DataApplied` → `LoadDataAndInitUi()` + status).

### 5.2 Calls into

| dependency | functions | purpose |
|---|---|---|
| `DataStore` | `AppFolder`, `SettingsFile`, `Load()`, `SerializeForSave()`, `LoadSettings()`, `ApplySyncedData()`, `AppIdentity` | read/write the database and settings; identity for `From` |
| `AppRepository` (via MainWindow) | `Save()`, `IsDirty` | pre-open flush |
| `MainWindow` | `FlushAllEditors()`, `LoadDataAndInitUi()` | pre-open flush / post-apply reload |
| Net.Codecrete.QrCodeGenerator 2.0.6 | `QrCode.EncodeText`, `Size`, `GetModule` | QR generation |
| OpenCvSharp4 4.10 (+ `runtime.win`) | `VideoCapture` (DSHOW), `WeChatQRCode`, `Cv2.CvtColor`, `Mat` | camera + QR detection |
| System.IO.Compression | `DeflateStream` | raw DEFLATE |
| System.Text.Json.Nodes | `JsonNode/JsonObject/JsonArray/JsonValue` | JSON trees |

### 5.3 Windows-only APIs used

* **WPF**: `Window`, `TabControl`, `DispatcherTimer` (frame clock), `Dispatcher.BeginInvoke`, `BitmapSource.Create`
  (Bgra32, 96 dpi, frozen), `RenderOptions.BitmapScalingMode=NearestNeighbor`, `MessageBox`.
* **Win32 P/Invoke**: `kernel32!SetThreadExecutionState` (`ES_CONTINUOUS 0x80000000`, `ES_DISPLAY_REQUIRED 0x2`,
  `ES_SYSTEM_REQUIRED 0x1`).
* **OpenCV DirectShow** capture (`VideoCaptureAPIs.DSHOW`) and the **WeChat CNN QR detector** (Caffe models,
  loaded by path from `<AppFolder>/qrmodels/`); build trims `opencv_videoio_ffmpeg*`.
* Embedded manifest resources (`Assembly.GetManifestResourceStream`).

---

## 6. macOS adaptation notes

### 6.1 Module layout (Swift)

| Mac file (suggested) | contents | mirrors |
|---|---|---|
| `AACore/FlashSync/Base45.swift` | `enum Base45 { static func encode(_:[UInt8]) -> String; static func decode(_:String) -> [UInt8]? }` | §3.1 |
| `AACore/Util/CRC32.swift` (shared with ZIP) | `CRC32.checksum(_:)` | §3.2 |
| `AACore/Util/RawDeflate.swift` (shared with ZIP) | `compress(_:) throws -> [UInt8]`, `inflate(_:rawLength:) throws -> [UInt8]` | §3.3 |
| `AACore/FlashSync/Fountain.swift` | `struct QrRandom`, `enum Fountain { degree(_:_:), indices(_:_:) }` | §3.4–3.6 |
| `AACore/FlashSync/FlashFrame.swift` | `enum FrameKind: UInt8 { changeSet = 0, fullSnapshot = 1 }`, `struct ManifestFrame`, `struct DataFrame`, `enum FlashFrame { encodeManifest, encodeData, decode -> Frame? }` | §3.7 |
| `AACore/FlashSync/FlashEncoder.swift` | `final class FlashEncoder` (`init(payload:kind:label:session:chunkSize:) throws`, `next() -> String`, `manifest`, `chunkCount`, `static newSession()`; plus an internal `init(coded:rawBytes:…)` for vector tests) | §3.8 |
| `AACore/FlashSync/FlashDecoder.swift` | `final class FlashDecoder` (`ingest(_:)`, `finish() -> [UInt8]?`, `solvedCount`, `chunkCount`, `isComplete`, `label`, `manifest`) | §3.9 |
| `AACore/FlashSync/FlashChangeSet.swift` | `enum FlashChangeSet` with the §3.11 functions over `JSONValue` | §3.11 |
| `AACore/FlashSync/FlashSyncStore.swift` | baseline I/O, `buildOutgoing`, `preview`, `apply`, `IncomingChange` | §3.12 |
| `AACore/FlashSync/QR/QRCode.swift` (+ `QRSegment`, `ReedSolomon`) | pure-Swift port of Nayuki's generator | §3.10 / §6.3 |
| `AACore/FlashSync/QR/QRRaster.swift` | `CGImage` rendering (1 px/module or integer scale, 4-module quiet zone) | §3.10 |
| `AA/FlashSync/FlashSyncWindow.swift` | SwiftUI UI | §2.1–2.3 |
| `AA/FlashSync/FlashSender.swift` | frame clock, pre-rendering, keep-awake | FLASH-013…024 |
| `AA/FlashSync/FlashReceiver.swift` | `AVCaptureSession` + Vision on a serial queue | FLASH-030…041 |
| `AA/FlashSync/CameraPreview.swift` | `NSViewRepresentable` hosting `AVCaptureVideoPreviewLayer` | FLASH-036 |
| `Tools/FlashSyncInterop` (optional executable target) | same subcommands/outputs as the C# CLI, `Swift` prefix | FLASH-120 |

The brief forbids third-party packages: the QR generator is written in-house (Nayuki's algorithm is public and
MIT-licensed; keep an attribution comment if code structure is followed closely).

### 6.2 JSON tree (AACore `JSONValue`)

Implement every accessor rule of §3.11.10 — ordered objects with ordinal keys, number lexemes preserved, JSON null
distinct from absent for `containsKey`/count but equal to absent for `[key]`. Do **not** use
`JSONSerialization`/`Codable` for Flash Sync trees (they lose key order, number lexemes and ordinal key identity).
`ReadDataTree` = parse the exact bytes the Mac persistence layer would write for the current model.

### 6.3 QR generation on the Mac — what is needed

**Requirements (MUST):** alphanumeric segment for Base45 text; ECC **L** requested; smallest version 1…40 that
fits; correct Reed-Solomon (GF(256), primitive polynomial `0x11D`) including blocks whose data starts with many
zero codewords; valid format/version information; any valid mask; output as a module matrix.
**Parity (SHOULD):** bit-identical to Nayuki `encodeText(text, LOW)` — i.e. `boostEcl = true` (raise to M/Q/H when
it still fits in the same version), automatic mask chosen by minimum penalty (N1 = 3, N2 = 3, N3 = 40, N4 = 10,
Nayuki's finder-pattern history method; lowest mask index wins ties), terminator ≤ 4 zero bits, byte padding
`0xEC, 0x11` alternating, char-count bits for alphanumeric 9/11/13 (versions 1–9 / 10–26 / 27–40). Parity makes
Mac frames identical to Windows frames (golden tests possible) and inherits Nayuki's proven correctness.

**Why CoreImage is not enough:**
* `CIQRCodeGenerator` accepts only `inputMessage` (Data) and `inputCorrectionLevel`; there is no control of segment
  mode, version or mask, and Apple does not document mode selection (in practice the message is encoded as bytes).
  Byte mode would push data frames from v22 (105 modules) to v26 (121 modules): still decodable (the protocol says
  "~35 % less dense"), but modules get ~13 % smaller at the same display size, and the zero-padded-tail robustness
  cannot be verified or controlled. Its built-in margin is undocumented, so we could not rely on the 4-module
  quiet zone either.
* `CIBarcodeGenerator` + `CIQRCodeDescriptor(payload:symbolVersion:maskPattern:errorCorrectionLevel:)` does allow
  version/mask/level control, but the payload must be the **already error-corrected, interleaved codewords** — i.e.
  segment encoding, RS and interleaving must be written anyway, and mask selection needs the matrix. Not worth it
  as the generator; **useful as an independent cross-check in tests** (feed our codewords + chosen version/mask to
  `CIQRCodeDescriptor`, render, and compare module-for-module with our matrix).

**Rendering:** build a `CGImage` in `DeviceGray` 8-bit (0 = dark, 255 = light) at an **integer number of device
pixels per module**: `modulePx = floor(min(plateW, plateH) × backingScaleFactor / (size + 8))` (≥ 1), recomputed on
resize / screen change; draw pixel-aligned with interpolation off (`Image(decorative:scale:)` +
`.interpolation(.none)`, or a layer-backed `NSView` with `magnificationFilter = .nearest`). This is strictly crisper
than Windows' non-integer uniform stretch. Keep the 4-module quiet zone inside the image **plus** the 18-pt white
plate padding, white in both light and dark appearance.

### 6.4 Camera receive — AVFoundation + Vision

1. **Permission**: `NSCameraUsageDescription` in Info.plist (brief: set by `build-app.sh`), hardened-runtime
   entitlement `com.apple.security.device.camera` (and the sandbox camera entitlement if sandboxed). Check
   `AVCaptureDevice.authorizationStatus(for: .video)`; `.notDetermined` → `requestAccess`; `.denied/.restricted` →
   status text `Camera access is turned off for AA. Allow it in System Settings ▸ Privacy & Security ▸ Camera.`
   with an **Open System Settings** button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`).
   (Mac-only string — there is no Windows equivalent.)
2. **Enumeration (FLASH-030)**: `AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external,
   .continuityCamera, .deskViewCamera], mediaType: .video, position: .unspecified)`; show `localizedName` (real names
   are an improvement over "Camera 2"); preselect `AVCaptureDevice.default(for: .video)`. Keep **Rescan**; also
   refresh automatically on `AVCaptureDevice.wasConnectedNotification` / `wasDisconnectedNotification`. Empty list →
   the FLASH-031 text (Mac: "…Plug one in and press Rescan — or use the Send tab, which needs no camera at all.").
3. **Format (FLASH-034)**: lock the device and choose the format with the largest dimensions **≤ 1920 × 1080**
   (prefer exactly 1080p: 4K costs Vision time without helping a close target) and the highest
   `maxFrameRate` (60 if offered, per protocol §11); set `activeVideoMin/MaxFrameDuration` accordingly; fall back to
   `sessionPreset = .high`. Focus: `.continuousAutoFocus` where `isFocusModeSupported` (most Mac cameras are
   fixed-focus; near-range restriction / smooth-AF are not available on macOS — skip silently).
4. **Output**: `AVCaptureVideoDataOutput`, `alwaysDiscardsLateVideoFrames = true` (≙ buffer size 1), pixel format
   `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (Vision uses luma; cheaper than BGRA), delegate on a serial
   queue labelled `FlashSync capture`. Do **not** mirror the data connection.
5. **Detection (FLASH-037)**: per sample buffer, `VNDetectBarcodesRequest` with `symbologies = [.qr]` (latest
   revision) via `VNImageRequestHandler(cvPixelBuffer:orientation: .up)`; feed **every**
   `observation.payloadStringValue` (multiple per frame) to `FlashDecoder.ingest` **without trimming**. Apple Vision
   is the detector the iOS side verified (100 % reassembly in its optical loop) and it has none of ZXing's mask-0
   problem. (The modern Swift `DetectBarcodesRequest` API is equally fine.) If Vision is still busy, drop the frame.
6. **Preview (FLASH-036)**: `AVCaptureVideoPreviewLayer` (`videoGravity = .resizeAspect`) on a black rounded plate
   (radius 4, min height 280) — GPU-composited, so the Windows 100 ms throttle is unnecessary. Mirroring the
   *preview* for built-in front cameras is optional (natural hand-eye feel); the data path stays unmirrored.
   Optional overlay: outline the detected code from `observation.boundingBox` and pulse on each newly solved chunk.
7. **UI updates (FLASH-038)**: from the capture queue post `(solved, K, label, complete)` to the main actor at most
   ~15 Hz; completion triggers FLASH-041 exactly once (the `_applying` guard ≙ an `isApplying` flag checked on both
   queues).
8. **Errors (FLASH-039)**: `AVCaptureSession.runtimeErrorNotification` → `Camera error: {localizedDescription}`;
   device disconnect / no sample buffer for > 1.2 s after start (watchdog) → `The camera stopped sending frames.`;
   `canAddInput` false or input creation throws → `That camera could not be opened. Another app may be using it.`
   / `Could not start the camera: {message}`; `wasInterrupted` → treat like "stopped sending frames". In every case
   stop the session and restore button states.
9. **No model files**: the WeChat Caffe models and the `qrmodels/` folder are not ported. A `qrmodels/` folder found
   in a data folder copied from Windows is ignored.
10. **Guidance copy (Mac-specific, optional addition to FLASH-040)**: MacBook/Studio Display cameras are fixed-focus
    and face the user; suggest "hold the phone 25–40 cm from the camera, filling at least half the preview". A
    Continuity Camera from a *different* iPhone/iPad, or any USB webcam, also works.

#### 6.4.4 Optional: receive from the screen (FLASH-133)

ScreenCaptureKit (`SCStream`, 30–60 fps, one window or a display region) + the same Vision path. Chief use: the
**iPhone Mirroring** app shows the phone's flashing screen pixel-perfect on the Mac — no camera, no focus, no glare.
Needs Screen Recording permission. Also a zero-hardware self-test (Mac flashes in one window, receives from it).

### 6.5 Send — frame clock, keep-awake, display

* **Clock (FLASH-015/023)**: drive frames from a display link (`NSView.displayLink(target:selector:)`, macOS 14+) or
  `NSScreen.displayLink`, advancing to the next frame when `elapsed ≥ 1/fps`, so every code is held for a whole
  number of refreshes (≥ 4 at 60 Hz for 15 fps) — steadier than `DispatcherTimer`'s ~15.6 ms granularity. Keep
  "Speed 6…15, default 12, `{n} / sec`".
* **Pre-render**: `encoder.next()` + QR matrix + `CGImage` for frame n+1 on a background serial queue while frame n
  is shown; the encoder is confined to that queue.
* **Keep-awake (FLASH-024)**: `ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled,
  .idleSystemSleepDisabled, .userInitiated], reason: "Flash Sync is showing QR codes")` on Start; `endActivity` on
  Stop / confirm / close (≙ ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED). This also keeps the screen saver off.
  Optionally hold `.idleSystemSleepDisabled` while *receiving* too (a sleeping Mac stops the camera).
* **Brightness**: macOS has no public API to raise display brightness — show a hint (`Turn your screen brightness
  up — it is the biggest factor in a clean capture.`). Optional: hide the cursor over the plate while flashing
  (`NSCursor.setHiddenUntilMouseMoves(true)`).
* **Photosensitivity note**: the plate changes pattern at up to 15 Hz; overall luminance is roughly constant, but
  consider a one-line caution the first time, and never add colour/brightness animation to the plate.

### 6.6 Window, modality and concurrency

* Recommended: a single-instance SwiftUI `Window("Flash Sync with iPhone", id: "flash-sync")` (not a sheet), so the
  user can drag the QR to the brightest display or go full screen (FLASH-134). To keep Windows' modal guarantees
  without blocking the app:
  1. on open and before every `prepareSend()`: flush all editors in all windows + blocking save (FLASH-002);
  2. the pending baseline is captured with the payload (FLASH-021), so edits made while the window is open are
     simply sent next time — correct by construction;
  3. `prepareSend()` must never run while flashing (it would change the session mid-transfer); when the window
     becomes key and is idle (not flashing, no confirm pending), re-run it so the summary isn't stale (Windows needs
     no such refresh because it is modal);
  4. before `apply`: flush + save; after `apply`: `AppStore.reloadFromDisk()` (open item windows re-resolve by `Id`,
     per the multi-window design), apply the theme (FLASH-130), status-bar text
     `Applied changes received from the iPhone`.
  A document-modal `.sheet` on the main window is an acceptable simpler alternative (closer to `ShowDialog`).
* Layout (native): toolbar with a segmented `Picker` **Send | Receive** (SF Symbols `qrcode`, `camera.viewfinder`),
  Start/Stop toolbar buttons (`play.fill` / `stop.fill`), `Rescan` (`arrow.clockwise`). Send: summary + hint on top,
  the white plate as the hero, bottom: `Speed` slider with `12 / sec`, progress text, a prominent
  **The iPhone says it got it** (`checkmark.seal`) button with the caution text. Receive: camera `Picker`, hint,
  preview plate, `ProgressView(value: solved, total: K)`, status line, bold `Incoming: …` line. Background uses the
  window material; header in the app accent token; muted text in the secondary label colour. The QR plate stays
  white and the preview plate black in both appearances.
* Dialogs: `NSAlert` (sheet on the Flash Sync window). Keep the exact message texts; Mac-style buttons with the
  **safe button as the default (Return)** to match Windows' `defaultResult: No`:
  * confirm-received: **Yes, It Finished** / **Not Yet** (default, Esc);
  * apply: **Apply** (destructive style for a snapshot) / **Don't Apply** (default, Esc);
  * errors/info: **OK**.
* Keyboard: Return activates the focused primary button only; `⌘.` = Stop (flashing or camera); `⌘W` closes (stopping
  everything first, FLASH-005). No Windows shortcuts exist to map.
* Accessibility: the plate image gets `accessibilityLabel("Flash Sync code")` and hides frame churn from VoiceOver;
  post an announcement on completion / damage / apply.
* Copy: substitute "this Mac" for "this PC" in the intro text and the snapshot warning; keep every other string
  (including the iPhone menu paths, which name the phone's own UI). Three ASCII dots may become `…`.

### 6.7 Settings & data plumbing on the Mac

* `readSettingsTree()` reads `settings.json` raw (AACore `JSONValue`); `writeSettingsTree()` writes it compact, then
  the Mac `SettingsStore.load()` re-reads, and the synced-data path rewrites through the settings model preserving
  unknown keys (brief: unknown members preserved).
* `applySyncedData(json)` ≙ `DataStore.ApplySyncedData`: switch the active data file to the default `data.json`,
  write with local at-rest encryption if enabled (AES-GCM/Keychain on Mac), load through the tolerant model,
  migrate legacy absolute attachment paths (handle both `\` and `/`, `…/files/<name>` → `files/<name>`), write again,
  persist settings; never touch `files/`.
* Baseline: same file name and JSON shape. When `EncryptLocalData` is on, the Mac **may** store the baseline
  encrypted with the same local key (it's per-device, never portable, so this doesn't affect compatibility); reads
  must accept plaintext too (§8 Q-11).

### 6.8 Nothing is impossible on the Mac

Every capability maps to a native API: DPAPI-free, OpenCV-free, DirectShow-free. The only genuinely different piece
is camera naming/format control (better on the Mac) and focus control (weaker on built-in Mac cameras — mitigated by
guidance, external/Continuity cameras, or FLASH-133 screen capture).

---

## 7. Test vectors and verification

All of these should become `AACoreTests` cases. §7.1–7.4 and §7.6 (first two rows) are the protocol's own vectors
(the C# `vectors` command runs them); everything marked *extra* was generated by the C#-faithful replica.

### 7.1 Base45

| input | encode |
|---|---|
| `""` | `""` |
| `"A"` | `K1` |
| `"AB"` | `BB8` |
| `"Hello!!"` | `%69 VD92EX0` |
| `"base-45"` | `UJCLQE7W581` |
| bytes `00 01 FE FF` | `100TAW` |

Decode (*extra*): `"A"` → nil (len%3==1); `"GGW"` → nil (65536 > 0xFFFF); `"FGW"` → `FF FF`; `"Z5"` → nil
(260 > 255); `"YR"` → nil (1249 > 255); `"abc"` → nil (lowercase); `"HELLO WORLD!"` → nil (`!`); `"AB8$AAé"` → nil
(non-ASCII). Round-trip property: `decode(encode(x)) == x` for random x of length 0…2000.

### 7.2 CRC-32

`""` → `00000000`; `"123456789"` → `CBF43926`; `"AA flash sync"` → `CD539EA5`; *extra*: 900 zero bytes →
`D5B7BCEC`.

### 7.3 xorshift32 (first 8 outputs)

| seed | outputs |
|---|---|
| 1 | 270369, 67634689, 2647435461, 307599695, 2398689233, 745495504, 632435482, 435756210 |
| 12345 | 3336926330, 1697253807, 2816511904, 1955480042, 718842323, 3283620450, 4285686168, 3680911160 |
| 0 (→0x9E3779B9) | 1359758873, 3761132862, 2075758394, 25405621, 3862129951, 4186559031, 3122997712, 4244368831 |
| *extra* 0xFFFFFFFF | 253983, 4228382207, 1958451267, 4056713434, 2049502865, 2560970988, 1705115568, 279806459 |
| *extra* 100 (first 4) | 27036706, 2466775534, 4119103220, 3457990521 |

### 7.4 Degree (K = 1000) and indices

Degree: r=0→1, 83→1, 84→2, 553→2, 554→3, 1023→60, 1024→1, 4294967295→60; *extra*: 918→12, 962→20, 999→35;
caps: `Degree(1023, K=10)` = 10, `Degree(941, K=9)` = 9.

Indices (protocol — **must pass before anything else**):

| seed | K | indices |
|---|---|---|
| 0 | 5 | [0] |
| 3 | 5 | [3] |
| 7 | 5 | [2] |
| 99 | 5 | [4] |
| 0 | 100 | [0] |
| 99 | 100 | [99] |
| 100 | 100 | [34] |
| 101 | 100 | [47] |
| 5000 | 100 | [64, 90] |
| 65535 | 100 | [50] |

*Extra* rows:

| K | seed → indices |
|---|---|
| 8 (cycling) | 0→[0], 7→[7], 8→[0], 9→[1], 15→[7], 4294967295→[7] |
| 9 | 8→[8], 9→[6,7], 10→[6,7], 11→[0,5], 12→[4,7], 1000→[0,7], 4294967295→[2] |
| 10 | 9→[9], 10→[0,1], 11→[1,6], 12→[3,8], 13→[2,7], 1000→[0,7], 4294967295→[7] |
| 12 | 11→[11], 12→[1,4], 13→[5,8], 14→[6,11], 15→[10,11], 1000→[4,9], 4294967295→[11] |
| 20 | 19→[19], 20→[0,7,18], 21→[5,6,17], 22→[0,2,9,15], 23→[2,11,16,19], 1000→[0,17], 4294967295→[7] |
| 100 | 102→[0,10], 103→[65], 1000→[40,77], 4294967295→[7] |
| 165 | 164→[164], 165→[11,155], 166→[105,148], 167→[1,73], 168→[23,157], 1000→[40,72], 4294967295→[137] |
| 1000 | 999→[999], 1000→[340,577], 1001→[369,488], 1002→[107,382], 1003→[66,427], 4294967295→[207] |
| 65535 | 65534→[65534], 65535→[4745], 65536→[6518], 65537→[6013], 65538→[44408], 1000→[1000], 4294967295→[64007] |

`indices(_, 0)` → `[]`; `indices(_, -1)` → `[]`.

### 7.5 Frames

Manifest `session=0x1234, codedBytes=1129, rawBytes=3075, chunkSize=900, chunkCount=2, crc32=0x3D3150F8,
kind=changeSet, label="1 equipment"`:
bytes `414151010012340000046900000C03038400023D3150F8000B312065717569706D656E74`,
QR text `AB8$AAI00$P6400FCDC006H0.UGXC0OA6%FVUI1D44KFE$EDF$DG/D`.

Data `session=0x1234, seed=7, payload=00…0F`:
bytes `4141510101123400000007000102030405060708090A0B0C0D0E0F`,
QR text `AB8$AA460$P6000$*0X507H0QS00+0J61%H1CT1F0`.

*Extra*:
* snapshot manifest `session=0xBEEF, codedBytes=437000, rawBytes=3100000, chunkSize=900, K=486, crc=0xDEADBEEF,
  kind=fullSnapshot, label="full database"` → bytes
  `4141510100BEEF0006AB08002F4D60038401E6DEADBEEF010D66756C6C206461746162617365`, QR text (57 chars)
  `AB8$AAA40T9U.$0N014:596C/UGH8TI/LU9UAV10%E5UD2VC3WEUJCLQE`.
* all-zero data frame `session=0x1234, seed=0, 900 zero bytes`: 911 bytes → 1367 chars, begins
  `AB8$AA460$P6` followed by `000` repeated to the end (the tail-padding case that broke QRCoder).
* label truncation: label = 61 × `é` (122 bytes) → labelLen byte `0x78` (120), label = 60 × `é`; label = `a` + 60 ×
  `é` (121 bytes) → 120 bytes kept, decoded label = `a` + 59 × `é` + `U+FFFD`.
* decode rejections: 4 bytes → nil; `41 41 51 02 …` (version 2) → nil; manifest with chunkSize 0 or K 0 → nil;
  manifest kind byte 2 → nil; manifest `labelLen` larger than remaining bytes → nil; data frame of exactly 11 bytes
  → nil; type byte 2 → nil; manifest with 3 trailing garbage bytes after the label → accepted (label unaffected).

### 7.6 DEFLATE

* Inflate `73748401273870860300` with rawLength 30 → `414141414141414141414242424242424242424243434343434343434343`.
* Our compressor's first byte ≠ `0x78` (not zlib-wrapped).
* *Extra (Mac)*: Apple `COMPRESSION_ZLIB` compressing those 30 bytes yields exactly `73748401273870860300`
  (identical to iOS); compressing empty input yields `0300`.
* Inflate with rawLength 10 → first 10 bytes (excess ignored, success); rawLength 40 → failure (only 30 produced).

### 7.7 Encoder / decoder (fountain layer)

Emission order for any K: `M, 0,1,2,3,4,5,6,7,8,9,10, M, 11,…,21, M, 22, …` (26 first: `M 0…10 M 11…21 M 22`).

*Extra* fixed vector (use the test-only `init(coded:…)` so DEFLATE is out of the loop): coded = 38 bytes
`030A11181F262D343B424950575E656C737A81888F969DA4ABB2B9C0C7CED5DCE3EAF1F8FF06` (byte i = (7i+3) & 0xFF),
chunkSize 4 → **K = 10** (last chunk `FF 06 00 00`), CRC `F7549EBA`, session `0x0102`, rawBytes 123, kind 0,
label `test`:
* manifest bytes `41415101000102000000260000007B0004000AF7549EBA000474657374`, QR text
  `AB8$AA100HB00008 4000XOFYM0HH1HVA6NNFP06$CQ2` (**contains a space** — never trim);
* data frames (seed → indices → payload hex → QR text):

| seed | idx | payload | QR text |
|---|---|---|---|
| 0 | [0] | `030A1118` | `AB8$AAW50HB0000300CC1O0` |
| 1 | [1] | `1F262D34` | `AB8$AAW50HB0000H608$471` |
| 2 | [2] | `3B424950` | `AB8$AAW50HB0000VC04H8Z1` |
| 3 | [3] | `575E656C` | `AB8$AAW50HB00000J00.BI2` |
| 4 | [4] | `737A8188` | `AB8$AAW50HB0000EP0-LF13` |
| 5 | [5] | `8F969DA4` | `AB8$AAW50HB0000SV0$1JT3` |
| 6 | [6] | `ABB2B9C0` | `AB8$AAW50HB0000.$0XQMC4` |
| 7 | [7] | `C7CED5DC` | `AB8$AAW50HB0000B:0T6Q+4` |
| 8 | [8] | `E3EAF1F8` | `AB8$AAW50HB0000P51PVTN5` |
| 9 | [9] | `FF060000` | `AB8$AAW50HB0000*B16Y000` |
| 10 | [0,1] | `1C2C3C2C` | `AB8$AAW50HB0000NC1TQ5:0` |
| 11 | [1,6] | `B49494F4` | `AB8$AAW50HB0000QL1BZIJ5` |
| 12 | [3,8] | `B4B49494` | `AB8$AAW50HB0000CR1D$MD3` |
| 13 | [2,7] | `FC8C9C8C` | `AB8$AAW50HB0000PY1-YH53` |
| 1000 | [0,7] | `C4C4C4C4` | `AB8$AAW50HB03008JTH*OG4` |

Decoder behaviour on that stream (assert `solvedCount` after each ingest):
* data before manifest (seed 0) → ignored, 0; manifest → 0 (K = 10); seed 10 → 0 (pending [0,1]);
  seed 11 → 0 (pending [1,6]); seed 1 → **3** (1 solves, cascades to 0 via seed 10 and to 6 via seed 11);
  seed 10 again → 3 (duplicate seed ignored); seeds 2,3,4,5,7,8 → 9; seed 12 ([3,8], both known) → 9 (redundant);
  seed 9 → 10, `isComplete`; `finish()` → reassembles and truncates to the 38 coded bytes, the CRC **passes**
  (`F7549EBA`), but these synthetic bytes are not a valid DEFLATE stream (zlib: "invalid distance too far back"),
  so `finish()` must return **nil** without throwing — the "CRC ok, inflate fails" path. The end-to-end variant
  (real DEFLATE'd JSON through the public initializer) must return the original bytes.
* a manifest with a different session (or CRC) mid-way → `solvedCount` back to 0 and the new K adopted; a manifest
  with the same session + CRC but different label → ignored (label unchanged).
* data frame whose payload length ≠ chunkSize → ignored; data frame of another session → ignored.

End-to-end (from the protocol build order and PROGRESS):
* loopback: encode a 60 KB JSON, drop a random 40 % of frames, decode → byte-equal;
* late join: start ingesting at emitted frame 37 → still completes;
* clean capture of K ≥ 9 without loss completes after exactly K data frames (1.00×);
* measured targets (20-run averages, protocol §1): K=4 → ≈10/18/34/66 frames at 0/25/50/70 % loss; K=12 →
  14/26/59/101; K=165 → 205/284/441/759 — assert "completes" and log counts, don't assert exact numbers;
* foreign text (`HELLO WORLD`, a URL, an empty string) never changes state;
* fuzz: 20 000 random byte strings wrapped in Base45 plus random mutations of valid frames → no crash, `finish()`
  never returns a payload whose CRC is wrong, never allocates > 64 MiB;
* `finish()` returns nil for: K·chunkSize > 64 MiB; codedBytes 0 or > K·chunkSize; rawBytes 0 or > 64 MiB; CRC
  mismatch; inflate short.

### 7.8 Change sets (inputs → exact compact outputs; created/now fixed at 2026-09-27 12:00:00)

**CS-1 build** — baseline
`{"Tasks":[{"Id":"a","Name":"A"},{"Id":"b","Name":"B"}],"Log":[{"Action":"Added","Name":"A"}],"Ui":{"WindowLeft":10,"TabColors":{"TabTasks":"#FF0000"},"SelectedMainTabIndex":2},"LastModified":"2026-09-01T10:00:00","SchemaVersion":1,"Sire":{"Bookmarks":[]}}`
current
`{"Tasks":[{"Id":"c","Name":"C"},{"Id":"b","Name":"B2"}],"Log":[{"Action":"Added","Name":"A"},{"Action":"Added","Name":"C"}],"Ui":{"WindowLeft":20,"TabColors":{"TabTasks":"#00FF00"},"SelectedMainTabIndex":3,"TabOrder":["TabTasks"]},"LastModified":"2026-09-02T10:00:00","SchemaVersion":1,"Sire":{"Bookmarks":[]}}`
baseline settings `{"DarkMode":false,"PasswordHash":"x","AppIdentity":"PC1","SyncOnSave":false}`, current settings
`{"DarkMode":true,"PasswordHash":"y","AppIdentity":"PC1","SyncOnSave":true}`, from `Windows` →
`{"V":1,"From":"Windows","Created":"2026-09-27T12:00:00","Sets":{"Tasks":[{"Id":"c","Name":"C"},{"Id":"b","Name":"B2"}]},"Deletes":{"Tasks":["a"]},"Blocks":{"Log":[{"Action":"Added","Name":"A"},{"Action":"Added","Name":"C"}]},"Order":{"Tasks":["c","b"]},"Settings":{"DarkMode":true},"UiChanges":{"TabColors":{"TabTasks":"#00FF00"},"TabOrder":["TabTasks"]}}`;
summary `2 Tasks, 1 deleted, Log, layout, settings`. (Per-device `WindowLeft`/`SelectedMainTabIndex`, excluded
`LastModified`, secret/policy settings all absent.)

**CS-2 apply CS-1** to receiver data
`{"Tasks":[{"Id":"a","Name":"A"},{"Id":"b","Name":"B"},{"Id":"z","Name":"Z"}],"Ui":{"WindowLeft":500,"SelectedMainTabIndex":0,"TabColors":{}},"LastModified":"2026-09-20T08:00:00","SchemaVersion":1}`
and settings `{"DarkMode":false,"PasswordHash":"mine","AppIdentity":"MAC1"}` →
data `{"Tasks":[{"Id":"c","Name":"C"},{"Id":"b","Name":"B2"},{"Id":"z","Name":"Z"}],"Ui":{"WindowLeft":500,"SelectedMainTabIndex":0,"TabColors":{"TabTasks":"#00FF00"},"TabOrder":["TabTasks"]},"LastModified":"2026-09-27T12:00:00.0000000","SchemaVersion":1,"Log":[{"Action":"Added","Name":"A"},{"Action":"Added","Name":"C"}]}`,
settings `{"DarkMode":true,"PasswordHash":"mine","AppIdentity":"MAC1"}`. (Receiver-only `z` survives after the
named ids; `Log` appended as a new key; `LastModified` updated in place.)

**CS-3 legacy `Blocks.Ui`**: change set
`{"V":1,"From":"iOS","Created":"2026-09-27T12:00:00","Blocks":{"Ui":{"WindowLeft":1,"WindowWidth":390,"SelectedMainTabIndex":4,"TabColors":{"TabCrew":"#123456"},"ShowShortcutBar":false}}}`
applied to `{"Ui":{"WindowLeft":500,"WindowWidth":1200,"SelectedMainTabIndex":0,"ShowShortcutBar":true},"Tasks":[]}`
→ `{"Ui":{"WindowLeft":500,"WindowWidth":1200,"SelectedMainTabIndex":0,"ShowShortcutBar":false,"TabColors":{"TabCrew":"#123456"}},"Tasks":[],"LastModified":"2026-09-27T12:00:00.0000000"}`;
summary `Ui`.

**CS-4 null ≡ removed**: baseline `{"Sire":{"Bookmarks":["1.1"]},"X":1,"Y":null}`, current `{"X":null,"Y":null}` →
`{"V":1,"From":"Windows","Created":"2026-09-27T12:00:00","BlockDeletes":["X","Sire"]}`; summary `REMOVES X, Sire`.

**CS-5 id-less element**: baseline `{"Tasks":[{"Id":"a"}]}`, current `{"Tasks":[{"Id":"a"},{"Name":"no id"}]}`
(no settings) → `{"V":1,"From":"Windows","Created":"2026-09-27T12:00:00","Blocks":{"Tasks":[{"Id":"a"},{"Name":"no id"}]}}`;
summary `Tasks`.

**CS-6 settings deletion only**: data `{}`/`{}`, current settings `{"GeminiApiKey":"k2"}`, baseline settings
`{"GeminiApiKey":"k","Foo":1}` → `{"V":1,"From":"Windows","Created":"2026-09-27T12:00:00","Settings":{},"SettingsDeletes":["Foo"]}`;
summary `settings, clears 1 setting`. (Note the empty `Settings` object is present.)

**CS-7 nothing but excluded keys changed**: current `{"LastModified":"2","Ui":{"WindowLeft":5}}`, baseline
`{"LastModified":"1","Ui":{"WindowLeft":4}}`, settings `{"AppIdentity":"B"}` vs `{"AppIdentity":"A"}` → **null**
(CLI writes `{}`, prints `no changes`).

**CS-8 number lexeme**: current `{"N":1}`, baseline `{"N":1.0}` → `{"V":1,…,"Blocks":{"N":1}}`.

**CS-9 append only → no Order**: baseline Tasks `[a,b]`, current `[a,b,c]` (objects `{"Id":…}`) →
`{…,"Sets":{"Tasks":[{"Id":"c"}]}}`; summary `1 Tasks`.

**CS-10 move → Order only**: baseline `[a,b]`, current `[b,a]` → `{…,"Order":{"Tasks":["b","a"]}}`; summary
`other changes`.

**CS-11 snapshot build**: data
`{"Tasks":[{"Id":"a"}],"Ui":{"WindowLeft":3,"TabColors":{"TabTasks":"#FF0000"},"GroupExpanded":{"Task|G":false}},"LastModified":"2026-09-02T10:00:00","SchemaVersion":1}`,
settings
`{"DarkMode":true,"PasswordHash":"h","PasswordSalt":"s","CurrentDataFile":"C:\\x\\data.json","AppIdentity":"PC1","GeminiApiKey":"k","NewKey":7}`
→ `{"V":1,"Data":{"Tasks":[{"Id":"a"}],"SchemaVersion":1,"Ui":{"TabColors":{"TabTasks":"#FF0000"}}},"Settings":{"DarkMode":true,"NewKey":7}}`.

**CS-12 snapshot apply** of CS-11's envelope onto existing
`{"Tasks":[{"Id":"q"}],"Ui":{"WindowLeft":900,"TabColors":{},"GroupExpanded":{"Task|H":true},"CrewSortMode":"Name"},"LastModified":"2026-09-25T10:00:00"}`
with settings `{"DarkMode":false,"PasswordHash":"mine","OnlyHere":1}` →
data `{"Tasks":[{"Id":"a"}],"SchemaVersion":1,"Ui":{"TabColors":{"TabTasks":"#FF0000"},"WindowLeft":900,"GroupExpanded":{"Task|H":true}},"LastModified":"2026-09-27T12:00:00.0000000"}`,
settings `{"DarkMode":true,"PasswordHash":"mine","OnlyHere":1,"NewKey":7}`, `hadSettings = true`. (Local shared
`CrewSortMode` is dropped — the sender's shared Ui wins wholesale in a snapshot.)

**CS-13 bare data.json snapshot**: payload `{"Tasks":[],"Ui":{"WindowTop":1,"TabOrder":["A"]}}`, existing
`{"Ui":{"WindowTop":77}}`, settings `{"DarkMode":false}` → `{"Tasks":[],"Ui":{"TabOrder":["A"],"WindowTop":77},"LastModified":"2026-09-27T12:00:00.0000000"}`,
settings unchanged, `hadSettings = false`.

**CS-14 Reorder edge**: target `[{"Id":"a","n":1},{"Name":"x"},{"Id":"b"},{"Id":"a","n":2},{"Id":"c"}]`, order
`["c","zz","a"]` → `[{"Id":"c"},{"Id":"a","n":1},{"Name":"x"},{"Id":"b"}]` (duplicate `a` dropped; id-less moved
after the named ones; `zz` skipped).

**CS-15 Sets into a non-array**: data `{"Crew":{"weird":true}}`, change set
`{"Sets":{"Crew":[{"Id":"1"}]},"Deletes":{"Tasks":["x"]}}` → `{"Crew":[{"Id":"1"}],"LastModified":"2026-09-27T12:00:00.0000000"}`.

**CS-16 per-device isolation (apply)**: `UiChanges` containing `WindowLeft`, `SelectedTaskId`, `GroupExpanded`,
`LastDigestDate` → none of them written; `UiDeletes` naming `WindowTop` → not removed.

**CS-17 excluded settings on apply**: `Settings` containing `PasswordHash`, `AppIdentity`, `CurrentDataFile` →
ignored; `DarkMode` merged; receiver-only keys untouched.

**CS-18 envelope detection**: `{"V":1,"Data":{}}` → envelope; `{"V":null,"Data":{}}` → not; `{"V":1,"Data":[]}` →
not; `{"Tasks":[]}` → not.

**CS-19 deep equals**: `{"a":1,"b":2}` == `{"b":2,"a":1}`; `[1,2]` ≠ `[2,1]`; `{"a":null}` ≠ `{}`; `"é"` (U+00E9)
== `"\u00e9"`; `"é"` ≠ `"e\u0301"`; `1` ≠ `1.0`; `"1"` ≠ `1`.

Byte-level cross-check: for every CS vector, the Mac output (compact, .NET-escaped) must equal the C# `cs-build` /
`cs-apply` / `snap-build` / `snap-apply` output byte-for-byte (run the C# CLI on a Windows/.NET machine or CI).

### 7.9 QR generation and optical loop (Mac)

* Base45 frames always select **alphanumeric** mode; the data frame for chunkSize 900 is **version 22, ECC L,
  105 modules**; manifest `full database` → v3 (29 modules) with ECC boosted to M; empty-label manifest → v2-M.
* Golden matrices: generate reference module grids for (a) the two protocol frame texts, (b) the all-zero data
  frame, (c) the K=10 manifest with the space, with Nayuki's reference implementation (e.g. `pip install qrcodegen`,
  `QrCode.encode_text(text, QrCode.Ecc.LOW)`), store as fixtures, and require bit-identical output (SHOULD).
* Independent check: render our codewords/version/mask through `CIQRCodeDescriptor` + `CIBarcodeGenerator` and compare
  module-for-module (validates placement, format and version bits).
* Synthetic optical loop (≙ Windows' "rendered QR → real detector → fountain reassembly"): render every frame of a
  real change set and of a K≈30 payload to `CGImage` at 3 px/module with quiet zone, run `VNDetectBarcodesRequest`,
  feed strings to `FlashDecoder` → byte-identical payload. Must include the all-zero tail frame and at least one
  symbol whose chosen mask is 0 (force mask 0 via the generator's test hook if needed).
* Degradations: scale down to 1.5 px/module, add blur/perspective (CoreImage `CIGaussianBlur`,
  `CIPerspectiveTransform`) — decode success rate should be reported, zero wrong payloads allowed.

### 7.10 UI / store tests

* `buildOutgoing` with no baseline → snapshot, label `full database`; with baseline equal to current → nil (UI shows
  "Nothing to send — …", Start disabled); after `writeBaseline(current)` → nil.
* `EstimateSeconds`: K=1, fps 12 → `2 seconds`; K=486, fps 12 → `ceil(54.675)+1 = 56` → `56 seconds`; K=486, fps 6
  → `ceil(109.35)+1 = 111` → `1 min 51 s`.
* Progress text: framesShown 1, K 2 → `0 full passes`; 2 → `1 full pass`; 5 → `2 full passes`.
* Send summary pluralisation: K = 1 → `1 piece`; K = 2 → `2 pieces`.
* Preview: snapshot kind with a change-set-shaped object → still snapshot; change-set kind with an envelope →
  snapshot; `[]` or invalid UTF-8/JSON → nil.
* Apply: baseline written after apply equals the tree re-read from disk; the active data file becomes the default
  `data.json`; `files/` untouched; unknown settings keys survive the settings rewrite.
* Interop (manual/CI): C# `encode` → Mac `decode` and Mac `encode` → C# `decode` at 0/30/60 % line-dropping and
  mid-stream starts (18/18 byte-identical on Windows↔iOS today); K≈950 stress.

---

## 8. Windows quirks, deviations and open questions

Each item states the Windows behaviour and the recommended Mac behaviour. Items marked **(keep)** must be reproduced
because they are wire- or data-visible; items marked **(fix)** are hardening that changes nothing on the wire for
well-formed peers.

* **Q-1 (fix, needs sign-off)** `BlockDeletes` is applied without an exclusion check: a malformed/legacy sender
  naming `Ui` would delete the whole local `Ui` (per-device keys included). Mac: skip `Ui` and `LastModified` in
  BlockDeletes. Similarly `Sets`/`Deletes`/`Order` naming `Ui` would replace `Ui` with an array — skip excluded keys
  there too.
* **Q-2 (fix, protocol-required)** `SettingsDeletes` is applied without filtering `ExcludedSettingsKeys`. The
  protocol says receivers must filter excluded keys on apply "so a legacy sender that still includes them cannot
  change anything" — an old iOS build that still diffs `PasswordHash` could otherwise **remove the receiver's master
  password**. Mac: filter SettingsDeletes through the same set.
* **Q-3 (fix, protocol-required)** The protocol says the very first iOS build shipped `Ui` "at the root" and
  receivers must fold it into the merge; Windows ignores a root-level `Ui` in a change set (safe, but loses those
  preferences). Mac: fold `changeSet["Ui"]` (object) into the merge with the lowest precedence (root < `Blocks.Ui` <
  `UiChanges`), per-device keys stripped. Confirm against the iOS `changesets.py` suite.
* **Q-4 (fix)** When `PrepareSend` yields nothing after a receive/apply, Windows keeps the previous encoder and
  pending baseline (and keeps flashing if it was flashing); confirming then would write a **pre-apply** baseline and
  echo the received changes back next time. Mac: on "nothing to send" clear the encoder and pending baseline, stop
  flashing, disable the confirm button.
* **Q-5 (fix)** An unreadable data file loads as an empty database; Flash Sync doesn't check `LastLoadFailed`, so it
  could flash a snapshot of nothing or a change set deleting everything. Mac: refuse to prepare/send (and to apply
  onto) a database in read-only safe mode, with the message `The database could not be read, so Flash Sync is
  unavailable until it is fixed.` Likewise an unreadable `settings.json` reads as `{}` and would emit
  SettingsDeletes for every shared key — treat unreadable (as opposed to absent) settings as an error.
* **Q-6 (keep)** A later manifest with the same session + CRC never replaces the first (so a mis-corrected first
  manifest with a wrong chunkSize/K can wedge the receiver until Stop/Start). Keep for parity; the UI recovery is
  "Stop, Start camera".
* **Q-7 (fix)** Rescan is not disabled while capturing on Windows; pressing it re-enables Start, and a second Start
  would leak the running camera. Mac disables Rescan and the picker while capturing.
* **Q-8 (keep)** `EstimateSeconds` is computed once per prepare; the slider does not refresh it. Mac may refresh it
  live (cosmetic).
* **Q-9 (keep)** `framesShown` is never reset for the window's lifetime (the pass count after a confirm keeps
  growing). Mac may reset it per prepare (cosmetic) — decide once, document.
* **Q-10 (fix)** "Failed to apply — your data was not changed." can be untrue: settings.json is written before
  `ApplySyncedData`. Mac: stage both and commit data first, settings second, or restore the previous settings.json on
  failure.
* **Q-11 (optional)** `qrsync-baseline.json` holds the whole database in plaintext even when `EncryptLocalData` is
  on. The Mac may encrypt it with the local key (per-device file; no compatibility impact).
* **Q-12 (keep, flag)** One baseline per device, regardless of peer. Syncing the same Mac with both an iPhone and a
  Windows PC measures "changes since the last confirmed transfer to **whichever** peer" — changes confirmed by one
  peer are never sent to the other. Document in help; per-peer baselines would be a protocol-level design change.
* **Q-13 (keep)** Incoming `DarkMode` is merged but Windows re-themes only on next launch; Mac applies it live
  (FLASH-130) — behaviour difference is visible but data-identical.
* **Q-14 (keep)** Snapshot summary never mentions missing settings on Windows; Mac adds FLASH-132 (protocol asks for
  it).
* **Q-15 (keep)** A change set that only reorders reads `other changes` in the summary.
* **Q-16 (keep)** `From` carries the free-text `AppIdentity` on Windows (not the literal "Windows" the protocol
  example shows). Mac sends its `AppIdentity`. Open: should the Mac send `macOS` for symmetry with iOS's `"iOS"`?
  Nothing reads it today.
* **Q-17 (keep)** Apply switches the active data file to the default `data.json` (a user who had "Save As…" onto
  another file is moved back to the default file).
* **Q-18 (open)** Should the Mac persist the Speed slider (per device, `UserDefaults` only — never settings.json)?
  Windows always starts at 12.
