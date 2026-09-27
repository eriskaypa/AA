# AA Flash Sync — protocol specification and Windows implementation handoff

**Status:** the iOS side is built, tested and shipping. The Windows side is not written yet.
This document is the complete contract; it is written to be read on its own, without the
Swift source.

**Version:** wire protocol `1` (the `AAQ\x01` magic). Any change to the framing, the PRNG,
the degree table, the index derivation or the compression is a **new version number**, not a
tweak — the two sides silently produce garbage otherwise.

---

## 1. What this is, and why it works this way

The iPhone and the Windows PC both hold the same `data.json`. Flash Sync moves the **text and
layout changes** between them with no cable, no network, no account and no shared folder: one
machine flashes a rapid sequence of QR codes on its screen, the other films it with a camera.

Attachments never travel this way — same contract as the "data only" `.aaz` export. This is
the text channel.

### The obvious design does not work

Chunk the payload, number the chunks `1..N`, loop through them. The receiver collects the
ones it sees and waits for the rest.

A camera does not see every frame a screen draws. Refresh rates beat against the sensor,
autofocus hunts, hands shake, rolling shutter tears frames in half. So the receiver ends up
holding 98 of 100 chunks and waiting through entire loops for the two it keeps missing — the
coupon-collector problem, where the tail costs more than everything before it. And because
this is a genuinely one-way channel, it cannot ask for a retransmission.

### What we do instead: a fountain

Every frame carries the **XOR of a pseudo-randomly chosen subset** of the source chunks,
identified only by the 32-bit **seed** that generated that subset. The receiver needs *any*
`K·(1+ε)` distinct frames — **it does not matter which ones**. Missing frames 3, 47 and 112
is irrelevant; the next three make up for them. The sender never needs to know what arrived,
which is exactly what makes a one-way optical channel practical.

Two refinements matter a lot in practice, and both are part of the contract:

- **Systematic prefix.** Seeds `0 .. K-1` are *defined* to be the plain, unmixed source
  chunks. A clean capture therefore decodes in one pass with no XOR arithmetic at all.
- **Small-payload cycling.** Below `K = 8`, fountain coding is counterproductive (too few
  chunks to peel efficiently) and plain round-robin wins outright. See §6.

### Measured behaviour

Frames the receiver must see before it can decode, filming mid-stream, averaged over 20 runs
per cell (this is the real, shipping implementation, not a model):

| payload | K | 0% loss | 25% loss | 50% loss | 70% loss |
|---|---|---|---|---|---|
| typical edit delta (12 KB) | 4 | 10 | 18 | 34 | 66 |
| bigger delta (60 KB) | 12 | 14 | 26 | 59 | 101 |
| **entire 3.1 MB database** | 165 | 205 | 284 | 441 | 759 |

At 15 frames per second that is **under a second for a typical edit**, and **14–50 seconds
for the whole database**. Zero decode failures in 480 trials.

Why the whole database is even feasible: `data.json` is 3.1 MB of JSON, which DEFLATEs to
**437 KB (7.2×)**. That is what gets chunked.

---

## 2. Payload pipeline

```
change set / snapshot JSON  (UTF-8, no BOM)
        │
        ├─ DEFLATE (raw, RFC 1951)        →  "coded" bytes; this is what gets chunked
        │
        ├─ split into K chunks of chunkSize, last one ZERO-PADDED
        │
        ├─ fountain: frame = XOR of the chunks selected by its seed
        │
        ├─ frame header + chunk  →  binary frame
        │
        └─ Base45 (RFC 9285)  →  the string that goes into the QR code
```

Reverse on the way in. Integrity is a CRC-32 over the **coded** (DEFLATE'd) bytes, checked
after reassembly and before inflate.

### Why Base45 and not Base64 or raw bytes

Base45's alphabet is *exactly* QR's alphanumeric charset, so the QR encoder packs it at
**5.5 bits per character** instead of 8. That recovers almost all of Base45's 1.5× expansion
and lands within ~3% of raw byte mode — while still arriving at the receiver as a plain
string. (Raw byte mode is a trap on iOS: `AVFoundation`'s QR reader hands back a `String` and
mangles true binary. Base45 sidesteps that entirely, in both directions.)

**Make sure your QR generator actually selects alphanumeric mode.** ZXing.Net and QRCoder both
auto-select it when every character is in the alphanumeric set, which Base45 guarantees. If a
generator forces byte mode the transfer still works correctly — it is just ~35% less dense.

---

## 3. Base45 (RFC 9285)

Alphabet, index 0..44:

```
0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:
```

(That is: digits, uppercase A–Z, then space `$` `%` `*` `+` `-` `.` `/` `:`.)

**Encode** — take bytes two at a time. For a pair `[a, b]`, let `n = a*256 + b`, then emit
three characters: `n % 45`, `(n / 45) % 45`, `n / 45 / 45`. A single trailing byte `a` emits
two characters: `a % 45`, `a / 45`.

**Decode** — the inverse. Three characters `[c0,c1,c2]` give `n = c0 + c1*45 + c2*45*45`,
which must be `≤ 0xFFFF`, and yield bytes `n >> 8`, `n & 0xFF`. Two trailing characters give
`n = c0 + c1*45`, which must be `≤ 0xFF`, and yield one byte. **One** trailing character is
invalid input. Any character outside the alphabet is invalid input.

Rejecting invalid input matters: it is how the receiver ignores QR codes that belong to
something else entirely.

### Test vectors

| input | output |
|---|---|
| `""` | `""` |
| `"A"` | `K1` |
| `"AB"` | `BB8` |
| `"Hello!!"` | `%69 VD92EX0` |
| `"base-45"` | `UJCLQE7W581` |
| bytes `00 01 FE FF` | `100TAW` |

---

## 4. DEFLATE

**Raw DEFLATE, RFC 1951 — no zlib wrapper, no gzip wrapper.**

- .NET: `System.IO.Compression.DeflateStream` is exactly right. Use it directly.
- Do **not** use `ZLibStream` or `GZipStream`.
- (iOS uses `COMPRESSION_ZLIB`, which despite the name is Apple's raw-DEFLATE stream and is
  wire-compatible with `DeflateStream`. Python needs `wbits=-15`.)

The decompressor is told the exact uncompressed length up front (`rawBytes` in the manifest),
so it can size its buffer exactly and verify the result.

**Cross-check vector.** Input (30 bytes, hex):

```
414141414141414141414242424242424242424243434343434343434343
```

Raw DEFLATE output produced by the iOS side (10 bytes):

```
73748401273870860300
```

Your implementation does **not** have to produce these exact bytes — DEFLATE encoders legally
differ. It **must** inflate them back to the input. Note the stream starts with `0x73`, not
`0x78`: if yours starts `78 9C` you have produced zlib-wrapped output and the other side will
reject it.

---

## 5. Deterministic PRNG — xorshift32

Both sides must generate byte-identical streams. Integer-only, no floating point anywhere.

```csharp
struct QrRandom {
    uint s;
    public QrRandom(uint seed) { s = seed == 0 ? 0x9E3779B9u : seed; }
    public uint Next() {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    }
    public int Next(int n) => (int)(Next() % (uint)n);
}
```

All shifts are on **unsigned 32-bit** values (`uint`, not `int` — a signed `>>` is an
arithmetic shift and will diverge). Overflow wraps; C# `uint` arithmetic already does this,
but do not enable `checked` arithmetic around it.

### Test vectors — first 8 outputs

| seed | outputs |
|---|---|
| `1` | 270369, 67634689, 2647435461, 307599695, 2398689233, 745495504, 632435482, 435756210 |
| `12345` | 3336926330, 1697253807, 2816511904, 1955480042, 718842323, 3283620450, 4285686168, 3680911160 |
| `0` (remapped to `0x9E3779B9`) | 1359758873, 3761132862, 2075758394, 25405621, 3862129951, 4186559031, 3122997712, 4244368831 |

---

## 6. Degree distribution and index derivation

### Degree table

A coarsened Robust Soliton distribution, expressed as an **integer cumulative table out of
1024**. It is a hardcoded table rather than computed Soliton maths specifically so that
floating-point differences between runtimes cannot desynchronise the two implementations.

```csharp
// (cumulative threshold out of 1024, degree)
static readonly (uint, int)[] DegreeCdf = {
    (84,1), (554,2), (718,3), (800,4), (851,5),
    (882,6), (903,7), (918,8), (942,12), (963,20),
    (1000,35), (1024,60)
};

static int Degree(uint r, int chunkCount) {
    uint x = r % 1024;
    foreach (var (threshold, d) in DegreeCdf)
        if (x < threshold) return Math.Min(d, chunkCount);
    return Math.Min(2, chunkCount);   // unreachable; defensive
}
```

Degree 2 dominates (46%) because pairs are what keep a peeling decoder fed.

| r | degree (K=1000) |
|---|---|
| 0 | 1 |
| 83 | 1 |
| 84 | 2 |
| 553 | 2 |
| 554 | 3 |
| 1023 | 60 |
| 1024 | 1 &nbsp;*(1024 % 1024 == 0)* |
| 4294967295 | 60 |

### Index derivation — the heart of the contract

```csharp
const int CyclingThreshold = 8;

static int[] Indices(uint seed, int chunkCount) {
    if (chunkCount <= 0) return Array.Empty<int>();

    // Small payloads: plain round-robin, no mixing at all.
    if (chunkCount <= CyclingThreshold)
        return new[] { (int)(seed % (uint)chunkCount) };

    // Systematic prefix: the first K seeds are the plain chunks.
    if (seed < (uint)chunkCount)
        return new[] { (int)seed };

    var rng = new QrRandom(seed);
    int degree = Degree(rng.Next(), chunkCount);
    var picked = new SortedSet<int>();
    int spins = 0;
    while (picked.Count < degree && spins < degree * 24) {
        picked.Add(rng.Next(chunkCount));
        spins++;
    }
    if (picked.Count == 0) picked.Add((int)(seed % (uint)chunkCount));
    return picked.ToArray();       // ASCENDING
}
```

Three details that will bite if you get them wrong:

1. **The first `rng.Next()` is consumed by the degree draw**, before any index is drawn.
2. **Duplicate draws are kept as duplicates in the spin count but collapse in the set** — the
   loop spins again rather than re-drawing into a different slot. The `degree * 24` cap keeps
   a pathological seed from wedging the encoder.
3. **The result is sorted ascending.** XOR is commutative so order does not affect the
   payload, but sorting keeps the two implementations comparable when you are debugging.

### Test vectors

| seed | K | indices |
|---|---|---|
| 0 | 5 | `[0]` |
| 3 | 5 | `[3]` |
| 7 | 5 | `[2]` &nbsp;*(cycling: 7 % 5)* |
| 99 | 5 | `[4]` |
| 0 | 100 | `[0]` |
| 99 | 100 | `[99]` &nbsp;*(last systematic)* |
| 100 | 100 | `[34]` &nbsp;*(first fountain frame)* |
| 101 | 100 | `[47]` |
| 5000 | 100 | `[64, 90]` |
| 65535 | 100 | `[50]` |

**If these ten rows do not reproduce exactly, stop and fix it before writing anything else.**
Everything downstream is built on them.

---

## 7. Frame format

All multi-byte integers are **big-endian**. These are the bytes *before* Base45.

### Common header (5 bytes)

| offset | size | field |
|---|---|---|
| 0 | 3 | magic — ASCII `A` `A` `Q` (`0x41 0x41 0x51`) |
| 3 | 1 | version — `0x01` |
| 4 | 1 | type — `0x00` manifest, `0x01` data |

Anything not starting `41 41 51 01` is not ours. Ignore it silently.

### Manifest frame (type 0)

| offset | size | field |
|---|---|---|
| 5 | 2 | `session` — u16, random per transfer |
| 7 | 4 | `codedBytes` — u32, DEFLATE'd length |
| 11 | 4 | `rawBytes` — u32, original length |
| 15 | 2 | `chunkSize` — u16 |
| 17 | 2 | `chunkCount` (K) — u16 |
| 19 | 4 | `crc32` — u32, over the DEFLATE'd bytes |
| 23 | 1 | `kind` — `0x00` change set, `0x01` full snapshot |
| 24 | 1 | `labelLen` — u8, bytes that follow (≤ 120) |
| 25 | n | `label` — UTF-8, human-readable, e.g. `3 tasks, 1 equipment` |

The manifest is re-shown **every 12th frame** so a receiver that starts filming late still
learns the shape of the transfer quickly.

### Data frame (type 1)

| offset | size | field |
|---|---|---|
| 5 | 2 | `session` — u16, must match the manifest |
| 7 | 4 | `seed` — u32 |
| 11 | `chunkSize` | payload — the XOR of the chunks `Indices(seed, K)` selects |

Every data frame is exactly `11 + chunkSize` bytes. The final source chunk is zero-padded to
`chunkSize`; the receiver truncates the reassembled result to `codedBytes`.

### Complete frame vectors

Manifest — `session=0x1234, codedBytes=1129, rawBytes=3075, chunkSize=900, chunkCount=2,`
`crc32=0x3D3150F8, kind=changeSet, label="1 equipment"`:

```
bytes : 414151010012340000046900000C03038400023D3150F8000B312065717569706D656E74
QR text: AB8$AAI00$P6400FCDC006H0.UGXC0OA6%FVUI1D44KFE$EDF$DG/D
```

Data — `session=0x1234, seed=7, payload = 00 01 02 … 0F`:

```
bytes : 4141510101123400000007000102030405060708090A0B0C0D0E0F
QR text: AB8$AA460$P6000$*0X507H0QS00+0J61%H1CT1F0
```

### CRC-32

Standard IEEE 802.3 / zip / PNG CRC-32 (a.k.a. CRC-32/ISO-HDLC): reflected, polynomial
`0xEDB88320`, initial value `0xFFFFFFFF`, final XOR `0xFFFFFFFF`.

| input | CRC-32 |
|---|---|
| `""` | `00000000` |
| `"123456789"` | `CBF43926` &nbsp;*(the standard check value)* |
| `"AA flash sync"` | `CD539EA5` |

---

## 8. Encoder

```
chunkSize = 900                     // see §11 for why
coded     = Deflate(payload)
K         = ceil(coded.Length / chunkSize)      // must be ≥1 and ≤ 65535
chunks[i] = coded[i*chunkSize .. ], zero-padded to chunkSize
manifest  = { session = random u16, codedBytes = coded.Length,
              rawBytes = payload.Length, chunkSize, chunkCount = K,
              crc32 = Crc32(coded), kind, label }

emitted = 0     // frames shown, drives the manifest cadence
seed    = 0     // NEXT seed to use — deliberately a SEPARATE counter

Next():
    if emitted % 12 == 0:
        emitted++
        return Encode(manifest)
    emitted++
    s = seed; seed++
    idx = Indices(s, K)
    body = chunks[idx[0]].Clone()
    for k in idx[1..]:  body ^= chunks[k]
    return Encode(DataFrame(session, s, body))
```

**Keep `seed` and `emitted` as separate counters.** If the manifest consumes a seed, then
chunks 0, 12, 24 … are never sent systematically, and a *perfectly clean* capture still pays
~1.3× fountain overhead to recover them. Separating the counters is what makes a clean
capture exactly 1.00×. (This was a real bug on the iOS side; it is measured in §1.)

The encoder never terminates. It loops forever until the user stops it.

---

## 9. Decoder — belief propagation ("peeling")

Each arriving frame is an equation over the unknown chunks. Substitute in everything already
solved; if exactly one unknown remains, that chunk is solved, and solving it cascades into
the equations still waiting.

State: `manifest`, `solved: Dictionary<int, byte[]>`, `pending: List<(HashSet<int>, byte[])>`,
`seenSeeds: HashSet<uint>`.

```
Ingest(text):
    frame = Decode(text)                       // null → not ours, ignore
    if frame is Manifest m:
        if manifest == null: manifest = m; return
        // A different session or CRC means the sender restarted, or the camera
        // wandered onto a different screen. Throw everything away rather than
        // mixing two transfers — that would silently corrupt the result.
        if m.session != manifest.session || m.crc32 != manifest.crc32:
            Reset(); manifest = m
        return

    if manifest == null: return                // header not seen yet
    if frame.session != manifest.session: return
    if frame.payload.Length != manifest.chunkSize: return
    if !seenSeeds.Add(frame.seed): return      // already had this exact frame

    idx = new HashSet(Indices(frame.seed, manifest.chunkCount))
    body = frame.payload
    foreach k in idx.ToList():
        if solved.ContainsKey(k): body ^= solved[k]; idx.Remove(k)

    if idx.Count == 0: return                  // fully redundant
    if idx.Count == 1: Solve(idx.Single(), body)
    else: pending.Add((idx, body))

Solve(index, value):
    queue = [(index, value)]
    while queue not empty:
        (i, v) = queue.Pop()
        if solved.ContainsKey(i): continue
        solved[i] = v
        still = []
        foreach (eqIdx, eqBody) in pending:
            if eqIdx.Contains(i):
                eqBody ^= v
                eqIdx.Remove(i)
                if eqIdx.Count == 0: continue           // became redundant, drop
                if eqIdx.Count == 1: queue.Push((eqIdx.Single(), eqBody)); continue
            still.Add((eqIdx, eqBody))
        pending = still

IsComplete = manifest != null && solved.Count == manifest.chunkCount

Finish():
    coded = concat(solved[0 .. K-1])
    coded = coded[0 .. manifest.codedBytes]              // drop the tail padding
    if Crc32(coded) != manifest.crc32: return FAILURE    // report, change nothing
    return Inflate(coded, manifest.rawBytes)
```

A CRC failure must be surfaced to the user and must leave their data untouched. It means
something got through the QR error correction corrupted, which is rare but not impossible.

---

## 10. Payloads

### Kind 1 — full snapshot

The payload is an **envelope carrying both files**:

```jsonc
{ "V": 1,
  "Data":     { /* data.json, byte-identical to the file both apps read and write */ },
  "Settings": { /* settings.json, minus the excluded keys below */ } }
```

Applying it replaces the whole database and merges the settings. Attachments on the receiving
device are left exactly as they are.

⚠️ **The envelope is not optional decoration.** With no baseline the sender cannot compute a
change set, so a snapshot is the ONLY way to pair two machines for the first time. The iOS build
first shipped this as the bare `data.json`, which meant dark mode and the container password
never crossed on that first pairing — a database whose containers were locked on the PC arrived
unopenable — and because the baseline written immediately afterwards recorded each side's OWN
settings, neither side ever detected a settings difference again. The hole was permanent.

**Readers must accept both shapes.** `data.json` has no top-level `Data` key, so the test is
unambiguous: an object with `V` and an object-valued `Data` is the envelope; anything else is a
bare `data.json` carrying no settings. Say so in the UI when settings are absent, rather than
implying they were synced.

### Kind 0 — change set

```jsonc
{
  "V": 1,
  "From": "Windows",                       // or "iOS"
  "Created": "2026-08-07T20:45:58",        // local time, no timezone suffix

  // Id-keyed collections: whole changed/new objects, keyed by collection name.
  "Sets":    { "Equipment": [ { "Id": "…", /* every other key, untouched */ } ] },
  "Deletes": { "Tasks": ["<id>", "<id>"] },

  // Every OTHER changed top-level key of data.json, whole. Ui lives here, and so
  // does anything that isn't an array of Id-bearing objects — scalars, objects
  // like "Sire", and arrays whose entries have no Id (e.g. "Log").
  "Blocks":       { "Ui": { … }, "Sire": { … }, "SchemaVersion": 3 },
  "BlockDeletes": ["SomeKeyThatDisappeared"],

  // Sequence for a collection, sent ONLY when applying the rest of this change
  // set would leave the receiver in a different order (see below).
  "Order": { "Tasks": ["<id>", "<id>", …] },

  // The whole of settings.json when it changed, minus the excluded keys below.
  "Settings":       { "DarkMode": true, "PasswordHash": "…", "PasswordSalt": "…" },
  // Keys REMOVED since the baseline. Required because settings are MERGED.
  "SettingsDeletes": ["PasswordHash", "PasswordSalt"]
}
```

Every one of `Sets`, `Deletes`, `Blocks`, `BlockDeletes`, `Order`, `Settings` and
`SettingsDeletes` is **omitted entirely when empty**.

#### `Order` — when to send it

Applying a change set replaces matched items in place and **appends** new ones, so the receiver's
resulting sequence is predictable. Compute it and only send `Order` when it would be wrong:

```
predicted = baselineIds − Deletes[name], then Sets ids not already present, appended
if predicted != currentIds:  Order[name] = currentIds
```

Adding an item at the end — the common case — therefore costs nothing. On apply, sort the
collection into the sent order; any Id the sender did not mention keeps its existing relative
position at the end rather than vanishing.

#### `SettingsDeletes` — why merging alone is not enough

Settings are applied by merging (see below), so a key *cleared* on one machine would otherwise
stand forever on the other. For `PasswordHash`/`PasswordSalt` that is a security bug, not a
cosmetic one: a password revoked on the PC would still unlock containers on the phone. Send
`keys(baseline) − keys(current)`, minus the excluded set, and remove them after merging. Treat a
deletion of either lock key as a lock change in whatever warning the receiving UI shows.

#### Diff EVERY key — do not use an allowlist

This is the part most likely to be implemented wrongly, because the obvious design is
wrong. Do **not** enumerate the collections you know about. Walk every top-level key
present in *either* the current tree or the baseline, and classify it structurally:

```
for name in union(currentKeys, baselineKeys):
    if name in EXCLUDED_DATA_KEYS: continue          // just "LastModified"
    if current[name] == baseline[name]: continue

    isCollection = isArrayContainingAnObjectWithAnId(current[name])
                || isArrayContainingAnObjectWithAnId(baseline[name])

    if !isCollection:
        Blocks[name] = current[name]                  // or BlockDeletes if gone
    else if any element of current[name] has NO "Id":
        Blocks[name] = current[name]                  // whole array; can't address items
    else:
        per-item diff by Id -> Sets[name] / Deletes[name]
```

The iOS build originally shipped a hardcoded list of twelve collections. It was wrong on
day one — the live database also has `Sire` (the whole SIRE 2.0 inspection: per-question
status, bookmarks, export flags, follow-up tasks and the user's own edited question
bodies) and `Trash` (soft-deleted items, each carrying the complete item payload for
undo) at top level, and neither was in the list. Both were silently dropped, with no
error anywhere. Diffing structurally fixes that class of bug permanently: a collection
added by a future version of *either* app syncs correctly without either app being
updated.

`Log` is the case that justifies the no-Id fallback: its entries have no `Id`, so it
ships as a whole block rather than losing entries.

**Excluded data.json keys:** `LastModified` only — the applier re-stamps it, so sending
it would make every change set differ for no reason.

#### settings.json

`settings.json` is a sibling file of `data.json`, not a key inside it, so it is diffed
separately and travels in `Settings`. Carrying it is what makes **dark mode** and the other
shared settings move between machines.

**Excluded settings.json keys — do not send these:**

| key | why |
|---|---|
| `GeminiApiKey` | A secret. A QR frame is a picture on a screen; anything in it can be filmed by any camera in the room and read at leisure. An API key is not worth that, and it is trivial to re-enter by hand. |
| `CurrentDataFile` | Absolute path on that machine. |
| `GoogleDriveFolder` | Absolute local path on that machine. |
| `FolderBuilderBase` | Absolute local path. |
| `SharedSaveFile` | Absolute local path. |
| `PasswordHash`, `PasswordSalt` | **Never sent.** Carrying them installs the SENDER'S master password on the receiver and locks that user out of their own database. |
| `EncryptLocalData` | At-rest encryption policy; flipping it requires rewriting the local file, so importing it would leave the on-disk state inconsistent. |
| `AppIdentity` | Per-install identity — both installs would otherwise claim to be the same machine in bundle stamps. |
| `SyncOnSave`, `TextOnlyExport` | Per-install policy. |

Echoing one machine's absolute path at another would quietly repoint it at a file that
isn't there, which is why those are excluded rather than merely useless.

> **Changed in the second revision.** The first draft of this spec had the iOS side *send* the
> password hash and salt, reasoning that a container encrypted on one machine should open on the
> other. The Windows implementation excluded them instead, arguing lockout — and that is the
> stronger argument: a user who cannot open *their own* database is a worse outcome than one
> container that needs the password re-entered. iOS now matches. Receivers must also filter these
> keys on **apply**, so a legacy sender that still includes them cannot change anything.

**Apply settings by MERGING, not replacing**, so keys the sender's build does not model
survive. ⚠️ **Windows-specific hazard:** the current Windows `WriteSettings` serialises a
fixed property DTO, so any key it does not model is dropped on its next settings write.
Fix that while you are here, or keys iOS writes will vanish on the next Windows save.

#### Applying a change set

In this order: upsert every `Sets` item by `Id` (replace in place, or append if new) →
remove every `Deletes` id → apply `Order` (after adds and removes, so every Id named exists) →
assign every `Blocks` key wholesale **except excluded keys and `Ui`** → remove every
`BlockDeletes` key → merge `UiChanges` into `Ui` and remove `UiDeletes` → merge `Settings` →
remove `SettingsDeletes` → stamp `LastModified` to now.

#### `Ui` — merged key by key, never replaced

`Ui` mixes two kinds of state, and the first two implementations each got one half wrong —
verified by running each side's real code against the other's:

* **iOS sent all of it**, as a whole `Blocks.Ui`. The Windows applier assigned blocks wholesale
  with no exclusion check, so an iPhone change set **deleted the PC's window position, size and
  maximised state, and jumped it to the phone's tab**.
* **Windows sent none of it**, so the **tab colours** the user explicitly asked to sync never
  reached the phone.

The rule now: `Ui` never travels as a block. Its **shared preferences** are diffed key by key and
sent as `UiChanges` (changed keys) and `UiDeletes` (removed keys) — exactly the model `Settings`
already uses. The receiver merges; it never replaces. That also means a concurrent change to a
*different* preference on the other side is not reverted, which a whole-`Ui` replace would do.

These **per-device** keys never travel and are never touched on apply, whatever a sender claims:

```
WindowLeft  WindowTop  WindowWidth  WindowHeight  WindowState
DueWindowWidth  DueWindowHeight
SelectedMainTabIndex
SelectedEquipmentId  SelectedTaskId  SelectedProcedureId  SelectedVesselId
CalendarSelectedDate  MapFocusedItemId
GroupExpanded        (which groups happen to be open — view state, not a choice)
LastDigestDate       (per-device reminder bookkeeping)
```

It is a **denylist** on purpose. An allowlist would silently stop every new preference from
syncing — the same failure mode as the original hardcoded collection list. Geometry and cursor
keys are a small, stable set; a new one that slips through costs a layout jump, not data.

**Legacy senders.** An iOS build from before this revision ships the whole `Ui` under `Blocks`
(or, in the very first build, at the root). Receivers must fold that into the same key-level
merge with the per-device keys stripped — never assign it. The iPhone in the user's hand at the
time of writing ran exactly such a build.

**Snapshots.** A snapshot carries `Ui` with the per-device keys removed. On apply, the receiver
takes the sender's shared preferences and keeps its own per-device keys.

An item that appears in both `Sets` and `Deletes` (only possible from a malformed sender)
ends up deleted; that is the safer reading.

**Changed items travel whole, not as field-level patches.** This is the same
zero-data-loss rule the rest of the app follows, and it is what makes checklist items,
subtasks, tags, per-item colours, rich text (`RichTextXaml`), schedules, components and
attachment *metadata* all ride across for free — they are simply part of the object. Do
not "clean up" or re-serialise items through a typed model on the way through; copy the
JSON subtree.

Items without an `Id` inside a collection cannot be addressed across devices, which is
what the whole-array fallback above is for.

### What deliberately does NOT travel

Everything a user can change travels, except these — each excluded on purpose, not by
oversight:

| not sent | why |
|---|---|
| **Attachment bytes** (`files/`) | The point of the channel. Their metadata — names, sizes, the item's reference — is text and *does* travel, so the far side knows a file exists even when it does not hold it. |
| **Secrets** (Gemini API key, Google OAuth tokens) | Never put a credential on a screen. OAuth tokens are device-bound anyway. |
| **Machine-local absolute paths** | Meaningless on the other machine, actively harmful if echoed back. |
| **Google Drive folder selection** | Useless without the OAuth token that cannot travel, and Windows targets a local folder path rather than a Drive folder id — a different mechanism entirely. |
| **Quick-switcher "recent items"** | Navigation history, not content; it is per-device by nature and regenerates in seconds. |
| **`LastModified`** | Re-stamped on apply. |
| **Sync bookkeeping** (`qrsync-baseline*.json`) | Per-device by definition. Shipping one would make a machine measure its changes against the *other* side's idea of "since when". |
| **Crash artefacts** (`data.unreadable.json`) | Not user data. |
| **Folder Builder output directories** | Real filesystem structure — the same category as attachments. |
| **OS permissions** (camera, notifications) | Not app state. |

| **Per-device `Ui` keys** (window geometry, cursor position — list above) | "Where you were", not "what you changed". An earlier revision of this document recorded the opposite call — ship `Ui` whole — for consistency with `.aaz` restores. Running the two implementations against each other showed what that costs: every iPhone sync reset the PC's window. A backup *restore* and an incremental *sync* have different intents, so they no longer need to match. |
| **The container password** | See the settings table: it would lock the receiver's user out. |

### The baseline

"What changed" is measured against a snapshot of the data tree taken **at the end of the last
completed sync**, stored beside the database (iOS: `qrsync-baseline.json` next to `data.json`).

Write the baseline at exactly two moments:

- after the user confirms the far side received what this machine sent, and
- after this machine applies something it received.

Both mean the same thing: the two sides are now known to agree on this state. With no baseline
there is nothing to measure against, so offer a full snapshot instead — sending one establishes
the baseline.

---

## 11. Display and capture guidance

### Displaying (the flashing side)

- **`chunkSize = 900`** puts a frame around QR version 20 at error-correction level **L** —
  dense enough to be quick, coarse enough that a camera locks on from across a desk. Use level
  L: the fountain handles loss far better than QR's own redundancy would, so every module spent
  on ECC is payload wasted.
- **8–15 frames per second**, user-adjustable, default 12. Faster is not automatically better:
  the camera must catch each code cleanly, and a display refreshing at 60 Hz should hold each
  QR for at least 4 refreshes.
- **Render the QR at native module scale with nearest-neighbour scaling.** Smoothed/interpolated
  edges cost far more decodes than a slightly smaller code does.
- **White background with a proper quiet zone** (≥4 modules) regardless of app theme, and turn
  the display brightness up. Brightness is the single biggest factor in capture reliability.
- **Suppress screensaver/sleep** while flashing.
- Show the label, `K`, and how many passes have gone by, so the user can see it is alive.
- Offer a **"the other side got it"** button — that, not a guess, is what advances the baseline.

### Capturing (the filming side)

- Prefer **1080p or better**; feed full frames to the detector.
- Request the **highest frame rate** the camera format allows (60 fps if available). Every
  extra camera frame is another chance to catch a code.
- **Continuous autofocus, near-range restriction if available, smooth-focus off.** A screen is
  a close, flat, bright target.
- ZXing.Net works well for the PC side. Enable `TryHarder`, restrict to `QR_CODE`, and — this
  matters — allow **multiple detections per frame** if your camera might see more than one.
- Feed *every* decoded string to the decoder and let it filter; it rejects foreign codes and
  duplicate seeds by itself.
- Show progress as `solved / chunkCount` plus the manifest's label, so the user knows what
  they are receiving and that it is advancing.
- **Never apply what arrives without showing the user what will change first.**

---

## 12. Suggested build order

1. **Base45**, then the §3 vectors.
2. **CRC-32** and **raw DEFLATE**, then the §4 and §7 vectors.
3. **xorshift32** and **`Indices`**, then the §5 and §6 vectors. *Do not proceed until all ten
   index rows match.*
4. **Frame encode/decode**, then the two complete frame vectors in §7.
5. **Encoder + decoder in a loopback test**: encode a payload, drop a random 40% of the frames,
   decode, assert byte equality. Then start the decoder mid-stream to prove late joins work.
6. **Change set build/apply**, round-tripped against a real `data.json`.
7. **Screen and camera**, last — by this point everything behind them is already proven.

A useful shortcut for step 7: the iOS app can flash real frames right now. Point the PC's
camera at it and you have a live conformance test against a known-good implementation before
writing a single line of Windows display code.

---

## 13. Cross-platform conformance

Both implementations exist, and they have been run **against each other**, through their real
shipping code — not just each against the vectors.

| suite | where | what it proves |
|---|---|---|
| spec vectors | Windows `Tests/FlashSync.Interop` → `vectors` | all 36 vectors in this document, re-run independently against the C# code |
| byte-level interop | iOS `Tests/CrossPlatform/run.sh` | iPhone encoder → PC decoder and PC encoder → iPhone decoder, at 0/30/60% loss, joining mid-stream: **18/18 byte-identical** |
| real-scale stress | (same harness, K≈950) | at roughly **twice the real database's chunk count**, 6/6 byte-identical up to 60% loss |
| change sets | iOS `Tests/CrossPlatform/changesets.py` | every scenario built on one side and applied by the other: item edits, `Ui` merge, per-device keys untouched, concurrent preference edits, deletion, password isolation, legacy senders, snapshots — **49 assertions** |

The change-set suite was run against the **unmodified** code first and failed exactly where the
`Ui` bugs described above predicted, so it demonstrably catches them.

Note that the two sides' DEFLATE encoders produce different compressed sizes from the same payload
(K=970 vs K=947 in the stress test). That is expected — §4 permits it — and the suite proves each
side inflates the other's output.

To run everything (needs Xcode's `swiftc`, `dotnet` 10, and both repos side by side):

```bash
WINDOWS_REPO=~/Documents/AA-latest ./Tests/CrossPlatform/run.sh
python3 Tests/CrossPlatform/changesets.py
```

The C# harness links the app's own four protocol files rather than copying them, and the whole
WPF app also compiles on macOS with `dotnet build AA/AA.csproj -p:EnableWindowsTargeting=true`
(it cannot run there — WPF and the OpenCV camera runtime are Windows-only).

## 14. iOS-side reference

| file | what is in it |
|---|---|
| `AA/RQRSync.swift` | Base45, CRC-32, DEFLATE, PRNG, degree table, framing, encoder, decoder |
| `AA/RChangeSet.swift` | change set build/apply, the baseline store |
| `AA/RViews/QRSyncViews.swift` | the flashing screen and the camera screen |
| `AA/RViews/FlashSyncViews.swift` | the Flash Sync menu and the review-before-apply sheet |

Reached from **More ▸ Backup & Transfer ▸ Flash Sync with PC**.

### What has actually been verified on the iOS side

- Base45, CRC-32, DEFLATE and frame codec round-trips, including rejection of foreign QR text.
- Fountain transfer across 480 simulated trials spanning 0–70% frame loss, both from the start
  of the stream and joining mid-stream — **zero decode failures**, numbers in §1.
- Change set build → encode → fountain at 45% loss → decode → apply, reconstructing the sender's
  tree **exactly**, including an unmodelled Windows-only key nested inside a new item.
- A true optical loop: QR codes rendered by the app, captured off the screen, decoded with
  Apple's Vision detector and fed back through the decoder — **100% reassembly** of a real
  one-item change set (2 frames, 3075 bytes), and correct manifest reads on the full 3.1 MB
  snapshot (512 frames).

The one thing not yet exercised is a real camera pointed at a real second screen — that needs
the Windows side to exist.
