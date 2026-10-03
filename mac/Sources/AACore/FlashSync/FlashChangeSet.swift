// Spec: 13 §3.11 / FLASH-080…095 (structural diff of every top-level key, Id collections, whole-array fallback,
//       Order only when needed, Blocks/BlockDeletes, Ui merged key by key, settings merge, envelope, apply order,
//       legacy senders, snapshots, human summary, deep equality, zero-data-loss transport), FLASH-107;
//       QR_SYNC_PROTOCOL.md §10; DECISIONS 13 Q-1/Q-2/Q-3 (receiver-side hardening, Deviations/W-FLASH.md).
// Pure over the AACore ordered `JSONValue` tree — items travel as JSON subtrees and are never re-serialised
// through the typed model on the way (unknown keys, RichTextXaml, enc: bodies, attachment metadata ride along).

/// Change-set / snapshot build and apply over `JSONObject` trees (System.Text.Json.Nodes semantics, 13 §3.11.10).
public enum FlashChangeSet {
    // MARK: Constant sets (13 §3.11.1) — identical on Windows, iOS and the Mac.

    /// data.json keys that never travel as a block: LastModified (re-stamped), Ui (merged key by key).
    public static let excludedDataKeys: [String] = ["LastModified", "Ui"]

    /// Ui keys that describe THIS workstation. A denylist on purpose: an allowlist would silently stop every new
    /// preference from syncing.
    public static let perDeviceUiKeys: [String] = [
        "WindowLeft", "WindowTop", "WindowWidth", "WindowHeight", "WindowState",
        "DueWindowWidth", "DueWindowHeight",
        "SelectedMainTabIndex",
        "SelectedEquipmentId", "SelectedTaskId", "SelectedProcedureId", "SelectedVesselId",
        "CalendarSelectedDate", "MapFocusedItemId",
        "GroupExpanded", "LastDigestDate",
    ]

    /// settings.json keys that never travel and are never written on apply (secrets, absolute paths,
    /// per-install identity/policy, the master password).
    public static let excludedSettingsKeys: [String] = [
        "GeminiApiKey", "CurrentDataFile", "GoogleDriveFolder", "FolderBuilderBase", "SharedSaveFile",
        "PasswordHash", "PasswordSalt", "EncryptLocalData", "AppIdentity", "SyncOnSave", "TextOnlyExport",
    ]

    /// The label of a full snapshot manifest.
    public static let snapshotLabel = "full database"
    /// The review summary of a snapshot.
    public static let snapshotSummary = "the sender's entire database (replaces yours)"

    private static let excludedData = Set(excludedDataKeys.map(Ordinal.Key.init))
    private static let perDevice = Set(perDeviceUiKeys.map(Ordinal.Key.init))
    private static let excludedSettings = Set(excludedSettingsKeys.map(Ordinal.Key.init))

    public static func isExcludedDataKey(_ k: String) -> Bool { excludedData.contains(Ordinal.Key(k)) }
    public static func isPerDeviceUiKey(_ k: String) -> Bool { perDevice.contains(Ordinal.Key(k)) }
    public static func isExcludedSettingsKey(_ k: String) -> Bool { excludedSettings.contains(Ordinal.Key(k)) }

    // MARK: Snapshot (kind 1)

    /// `{"V":1,"Data":{data minus LastModified, Ui reduced to its shared keys and moved to the end},
    /// "Settings":{settings minus excluded keys} | null}`.
    public static func buildSnapshot(data: JSONObject, settings: JSONObject?) -> JSONObject {
        var o = JSONObject()
        o.set("V", .number(JSONNumber(1)))
        o.set("Data", .object(stripExcludedData(data)))
        o.set("Settings", stripExcludedSettings(settings).map(JSONValue.object) ?? .null)
        return o
    }

    static func stripExcludedData(_ data: JSONObject) -> JSONObject {
        var o = JSONObject()
        for (k, v) in data where !isExcludedDataKey(k) { o.set(k, v) }
        if case .object(let ui)? = data["Ui"] { o.set("Ui", .object(sharedUi(ui))) }
        return o
    }

    /// A Ui object without the per-device keys (order kept).
    public static func sharedUi(_ ui: JSONObject) -> JSONObject { ui.filtering(excluding: perDevice) }

    /// An object with `V` (non-null) and an object-valued `Data` is the envelope; anything else is a bare data.json.
    public static func isSnapshotEnvelope(_ node: JSONValue?) -> Bool {
        guard case .object(let o)? = node, o["V"] != nil, case .object? = o["Data"] else { return false }
        return true
    }

    // MARK: Change set (kind 0)

    /// The structural diff of `current` against the baseline (every top-level key, no allowlist), plus settings
    /// and the shared Ui keys. nil when nothing changed (13 §3.11.4).
    public static func buildChangeSet(current: JSONObject, baselineData: JSONObject?, currentSettings: JSONObject?,
                                      baselineSettings: JSONObject?, from: String, created: NetDateTime) -> JSONObject? {
        var sets = JSONObject(), deletes = JSONObject(), blocks = JSONObject(), order = JSONObject()
        var blockDeletes: [JSONValue] = []

        for name in unionKeys(current, baselineData) {
            if isExcludedDataKey(name) { continue }
            let c = current[name]
            let b = baselineData?[name]
            if JSONValue.deepEquals(c, b) { continue }
            guard let c else { blockDeletes.append(.string(name)); continue }       // removed (absent or null)

            let isColl = isIdCollection(c) || isIdCollection(b)
            if !isColl { blocks.set(name, c); continue }
            guard case .array(let cArr) = c, cArr.allSatisfy(hasId) else {
                blocks.set(name, c)                                                 // can't address items → whole value
                continue
            }
            let (bIds, bMap) = orderedIds(b?.arrayValue)
            let (cIds, cMap) = orderedIds(cArr)

            var itemSets: [JSONValue] = []
            for id in cIds {
                let item = cMap[Ordinal.Key(id)]!
                if let old = bMap[Ordinal.Key(id)], JSONValue.deepEquals(item, old) { continue }
                itemSets.append(item)
            }
            if !itemSets.isEmpty { sets.set(name, .array(itemSets)) }

            let dels = bIds.filter { cMap[Ordinal.Key($0)] == nil }
            if !dels.isEmpty { deletes.set(name, .array(dels.map(JSONValue.string))) }

            let delSet = Set(dels.map(Ordinal.Key.init))
            var predicted = bIds.filter { !delSet.contains(Ordinal.Key($0)) }
            var predictedSet = Set(predicted.map(Ordinal.Key.init))
            for id in cIds where predictedSet.insert(Ordinal.Key(id)).inserted { predicted.append(id) }
            if !predicted.elementsEqual(cIds, by: Ordinal.equals) {
                order.set(name, .array(cIds.map(JSONValue.string)))
            }
        }

        let (settingsOut, settingsDeletes) = diffSettings(current: currentSettings, baseline: baselineSettings)

        var uiChanges = JSONObject()
        var uiDeletes: [JSONValue] = []
        let curUi = current["Ui"]?.objectValue
        let basUi = baselineData?["Ui"]?.objectValue
        if let curUi {
            for (k, v) in curUi where !isPerDeviceUiKey(k) && !JSONValue.deepEquals(v, basUi?[k]) { uiChanges.set(k, v) }
        }
        if let basUi {
            for (k, _) in basUi where !isPerDeviceUiKey(k) && !(curUi?.containsKey(k) ?? false) {
                uiDeletes.append(.string(k))
            }
        }

        if sets.isEmpty && deletes.isEmpty && blocks.isEmpty && blockDeletes.isEmpty && order.isEmpty
            && settingsOut == nil && settingsDeletes.isEmpty && uiChanges.isEmpty && uiDeletes.isEmpty {
            return nil
        }
        var cs = JSONObject()
        cs.set("V", .number(JSONNumber(1)))
        cs.set("From", .string(from))
        cs.set("Created", .string(created.format(.isoLocalSeconds)))
        if !sets.isEmpty { cs.set("Sets", .object(sets)) }
        if !deletes.isEmpty { cs.set("Deletes", .object(deletes)) }
        if !blocks.isEmpty { cs.set("Blocks", .object(blocks)) }
        if !blockDeletes.isEmpty { cs.set("BlockDeletes", .array(blockDeletes)) }
        if !order.isEmpty { cs.set("Order", .object(order)) }
        if let settingsOut { cs.set("Settings", .object(settingsOut)) }
        if !settingsDeletes.isEmpty { cs.set("SettingsDeletes", .array(settingsDeletes.map(JSONValue.string))) }
        if !uiChanges.isEmpty { cs.set("UiChanges", .object(uiChanges)) }
        if !uiDeletes.isEmpty { cs.set("UiDeletes", .array(uiDeletes)) }
        return cs
    }

    /// (whole stripped current settings, keys removed since the baseline) or (nil, []) when equal (13 §3.11.5).
    static func diffSettings(current: JSONObject?, baseline: JSONObject?) -> (JSONObject?, [String]) {
        let cur = stripExcludedSettings(current) ?? JSONObject()
        let bas = stripExcludedSettings(baseline) ?? JSONObject()
        if JSONValue.deepEquals(.object(cur), .object(bas)) { return (nil, []) }
        var deletes: [String] = []
        for name in unionKeys(bas, cur) where bas[name] != nil && cur[name] == nil { deletes.append(name) }
        return (cur, deletes)
    }

    // MARK: Apply

    /// Applies a change set to the data and settings trees in the contract's order (13 §3.11.6, FLASH-089):
    /// Sets → Deletes → Order → Blocks → Ui merge → BlockDeletes → Settings merge → SettingsDeletes → LastModified.
    /// Receiver hardening (DECISIONS 13 Q-1/Q-2/Q-3): excluded data keys are skipped in Sets/Deletes/Order/
    /// BlockDeletes, excluded settings keys in SettingsDeletes, and a root-level legacy `Ui` joins the merge.
    public static func applyChangeSet(_ changeSet: JSONObject, data: inout JSONObject, settings: inout JSONObject,
                                      now: NetDateTime) {
        // 1) upsert Sets by Id (replace in place, or append)
        if case .object(let sets)? = changeSet["Sets"] {
            for (name, arrNode) in sets where !isExcludedDataKey(name) {
                guard case .array(let items) = arrNode else { continue }
                var target = data[name]?.arrayValue ?? []
                for item in items {
                    guard case .object(let io) = item else { continue }
                    let at = indexOfId(target, io["Id"]?.idText)
                    if at >= 0 { target[at] = item } else { target.append(item) }
                }
                data.set(name, .array(target))
            }
        }

        // 2) remove Deletes ids (every element whose Id is named, duplicates included)
        if case .object(let dels)? = changeSet["Deletes"] {
            for (name, idsNode) in dels where !isExcludedDataKey(name) {
                guard case .array(let target)? = data[name], case .array(let ids) = idsNode else { continue }
                let idSet = Set(ids.map { Ordinal.Key(idString($0)) })
                let kept = target.filter { e in
                    guard let id = e.objectValue?["Id"]?.idText else { return true }
                    return !idSet.contains(Ordinal.Key(id))
                }
                data.set(name, .array(kept))
            }
        }

        // 3) Order (after adds and removes, so every named Id exists)
        if case .object(let order)? = changeSet["Order"] {
            for (name, idsNode) in order where !isExcludedDataKey(name) {
                guard case .array(let target)? = data[name], case .array(let ids) = idsNode else { continue }
                data.set(name, .array(reorder(target, ids.map(idString))))
            }
        }

        // 4) Blocks wholesale — never an excluded key (a JSON null value sets the key to null)
        let blocks = changeSet["Blocks"]?.objectValue
        if let blocks {
            for (name, val) in blocks where !isExcludedDataKey(name) { data.set(name, val) }
        }

        // 4b) Ui: legacy root `Ui` (lowest) < legacy `Blocks.Ui` < `UiChanges` (highest); then `UiDeletes`.
        var uiIn = JSONObject()
        if case .object(let rootUi)? = changeSet["Ui"] { uiIn.append(contentsOf: rootUi) }
        if case .object(let legacyUi)? = blocks?["Ui"] { uiIn.append(contentsOf: legacyUi) }
        if case .object(let uc)? = changeSet["UiChanges"] { uiIn.append(contentsOf: uc) }
        let uiDel = changeSet["UiDeletes"]?.arrayValue
        if !uiIn.isEmpty || !(uiDel?.isEmpty ?? true) {
            var localUi = data["Ui"]?.objectValue ?? JSONObject()
            for (k, v) in uiIn where !isPerDeviceUiKey(k) { localUi.set(k, v) }
            for n in uiDel ?? [] {
                let k = idString(n)
                if !isPerDeviceUiKey(k) { localUi.removeValue(forKey: k) }
            }
            data.set("Ui", .object(localUi))
        }

        // 5) BlockDeletes (excluded keys skipped — a malformed sender must not wipe Ui or LastModified)
        if case .array(let bdel)? = changeSet["BlockDeletes"] {
            for n in bdel {
                let k = idString(n)
                if !isExcludedDataKey(k) { data.removeValue(forKey: k) }
            }
        }

        // 6) merge Settings (never an excluded key)
        if case .object(let incoming)? = changeSet["Settings"] {
            for (k, v) in incoming where !isExcludedSettingsKey(k) { settings.set(k, v) }
        }

        // 7) remove SettingsDeletes (never an excluded key — a legacy sender cannot remove PasswordHash/Salt)
        if case .array(let sdel)? = changeSet["SettingsDeletes"] {
            for n in sdel {
                let k = idString(n)
                if !isExcludedSettingsKey(k) { settings.removeValue(forKey: k) }
            }
        }

        // 8) re-stamp LastModified (local wall time, 7 fraction digits, no offset)
        data.set("LastModified", .string(now.format(.isoLocal7)))
    }

    /// Applies a snapshot: the whole data tree is replaced (the sender's shared Ui wins, this device's per-device
    /// Ui keys are kept), settings are MERGED (no deletes). Accepts the envelope or a bare data.json
    /// (`hadSettings` false) (13 §3.11.7, FLASH-092).
    public static func applySnapshot(_ payload: JSONObject, settings: inout JSONObject, now: NetDateTime,
                                     existingData: JSONObject?) -> (data: JSONObject, hadSettings: Bool) {
        var data: JSONObject
        var hadSettings = false
        if isSnapshotEnvelope(.object(payload)), case .object(let d)? = payload["Data"] {
            data = d
            if case .object(let incoming)? = payload["Settings"] {
                hadSettings = true
                for (k, v) in incoming where !isExcludedSettingsKey(k) { settings.set(k, v) }
            }
        } else {
            data = payload
        }
        let incomingUi = data["Ui"]?.objectValue
        for k in excludedDataKeys { data.removeValue(forKey: k) }
        var mergedUi = incomingUi.map(sharedUi) ?? JSONObject()
        if case .object(let localUi)? = existingData?["Ui"] {
            for (k, v) in localUi where isPerDeviceUiKey(k) { mergedUi.set(k, v) }
        }
        if incomingUi != nil || existingData?["Ui"] != nil { data.set("Ui", .object(mergedUi)) }
        if let keep = existingData?["LastModified"] { data.set("LastModified", keep) }
        data.set("LastModified", .string(now.format(.isoLocal7)))
        return (data, hadSettings)
    }

    // MARK: Human summary (13 §3.11.8, FLASH-093)

    /// e.g. `2 Tasks, 1 deleted, Log, layout, settings`; destructive operations are always named; never "no changes".
    public static func summarize(_ changeSet: JSONObject) -> String {
        var parts: [String] = []
        if case .object(let sets)? = changeSet["Sets"] {
            for (name, arr) in sets {
                if case .array(let a) = arr, !a.isEmpty { parts.append("\(a.count) \(name)") }
            }
        }
        if case .object(let dels)? = changeSet["Deletes"] {
            let n = dels.reduce(0) { $0 + ($1.value.arrayValue?.count ?? 0) }
            if n > 0 { parts.append("\(n) deleted") }
        }
        if case .object(let b)? = changeSet["Blocks"], !b.isEmpty { parts.append(b.keys.joined(separator: ", ")) }
        let uiChanged: Bool = {
            if case .object(let u)? = changeSet["UiChanges"], !u.isEmpty { return true }
            if case .array(let u)? = changeSet["UiDeletes"], !u.isEmpty { return true }
            return false
        }()
        if uiChanged { parts.append("layout") }
        if case .array(let bd)? = changeSet["BlockDeletes"], !bd.isEmpty {
            parts.append("REMOVES " + bd.map { $0.isNull ? "?" : ($0.idText ?? "?") }.joined(separator: ", "))
        }
        if changeSet["Settings"] != nil { parts.append("settings") }
        if case .array(let sd)? = changeSet["SettingsDeletes"], !sd.isEmpty {
            parts.append("clears \(sd.count) setting\(sd.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "other changes" : parts.joined(separator: ", ")
    }

    // MARK: Helpers

    static func stripExcludedSettings(_ settings: JSONObject?) -> JSONObject? {
        settings?.filtering(excluding: excludedSettings)
    }

    /// `a`'s keys in order, then `b`'s keys not in `a` (ordinal).
    static func unionKeys(_ a: JSONObject?, _ b: JSONObject?) -> [String] {
        var seen = Set<Ordinal.Key>()
        var out: [String] = []
        for k in a?.keys ?? [] where seen.insert(Ordinal.Key(k)).inserted { out.append(k) }
        for k in b?.keys ?? [] where seen.insert(Ordinal.Key(k)).inserted { out.append(k) }
        return out
    }

    /// An object whose `Id` is present and not JSON null.
    private static func hasId(_ e: JSONValue) -> Bool { e.objectValue?["Id"] != nil }

    /// An array containing at least one object with a non-null `Id`.
    static func isIdCollection(_ n: JSONValue?) -> Bool {
        guard case .array(let arr)? = n else { return false }
        return arr.contains(where: hasId)
    }

    /// Ids (as text) in order of first occurrence, and the first element per id.
    static func orderedIds(_ arr: [JSONValue]?) -> ([String], [Ordinal.Key: JSONValue]) {
        var ids: [String] = []
        var map: [Ordinal.Key: JSONValue] = [:]
        for e in arr ?? [] {
            guard let id = e.objectValue?["Id"]?.idText else { continue }
            let key = Ordinal.Key(id)
            if map[key] == nil { ids.append(id); map[key] = e }
        }
        return (ids, map)
    }

    /// JsonNode `ToString() ?? ""` for an id/key entry.
    private static func idString(_ v: JSONValue) -> String { v.idText ?? "" }

    private static func indexOfId(_ arr: [JSONValue], _ id: String?) -> Int {
        guard let id else { return -1 }
        for (i, e) in arr.enumerated() {
            if let eid = e.objectValue?["Id"]?.idText, Ordinal.equals(eid, id) { return i }
        }
        return -1
    }

    /// Named ids first (requested order; absent ids skipped, a second element with a placed id dropped), then every
    /// other element in its original order — id-less elements therefore move after the named ones (13 §3.11.6).
    static func reorder(_ items: [JSONValue], _ orderIds: [String]) -> [JSONValue] {
        var byId: [Ordinal.Key: JSONValue] = [:]
        for e in items {
            if let id = e.objectValue?["Id"]?.idText, byId[Ordinal.Key(id)] == nil { byId[Ordinal.Key(id)] = e }
        }
        var used = Set<Ordinal.Key>()
        var rebuilt: [JSONValue] = []
        for id in orderIds {
            let key = Ordinal.Key(id)
            if let node = byId[key], used.insert(key).inserted { rebuilt.append(node) }
        }
        for e in items {
            if let id = e.objectValue?["Id"]?.idText, used.contains(Ordinal.Key(id)) { continue }
            rebuilt.append(e)
        }
        return rebuilt
    }
}
