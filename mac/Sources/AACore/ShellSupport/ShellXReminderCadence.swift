// Spec: 03 SHELL-130…133 (tray → MenuBarExtra, 30-min reminder, daily digest, crew-expiry surfaces), §6.8, §3.10;
//       02 REPO-112 (dedup key, balloon text, "nothing due → reset the key"), REPO-113 (once-a-day digest; set
//       LastDigestDate and MarkDirty even when nothing is due), §7.8; 09 CREW-092; DECISIONS 02 Q-7 / 03 Q-8 (also at
//       local day rollover; digest date tracked per device), Q-13 (UserNotifications + Dock badge + MenuBarExtra);
//       ARCHITECTURE.md §9.3. Vectors: 02 §7.8 "Digest", 03 §7.1 "Digest".
import Foundation

/// Why a reminder pass runs (ARCHITECTURE.md §7.7 `ReminderCenter.runDigest(reason:)`).
public enum ShellXReminderReason: String, Sendable, Equatable, CaseIterable {
    /// Main window shown with data (Windows OnLoaded step 19: digest, then the reminder check).
    case launch
    /// The 30-minute timer (Windows `_reminderTimer`: the reminder check only).
    case timer
    /// `NSCalendarDayChanged` while AA stays open (DECISIONS 02 Q-7): digest + check.
    case dayChanged
    /// `NSWorkspace.didWakeNotification` (ARCH §9.3 re-check; a wake can cross midnight): digest + check.
    case wake

    /// Reasons that also evaluate the once-a-day digest.
    public var includesDigest: Bool { self != .timer }
}

/// The once-a-day digest decision (REPO-113 + DECISIONS 02 Q-7 "digest date tracked per device").
public struct ShellXDigestDecision: Sendable, Equatable {
    /// Set `Ui.LastDigestDate = today` and `MarkDirty()` (REPO-113: whenever it differs from today).
    public var markUiDate: Bool
    /// This device has not shown today's digest: record today for it and, when anything is due, open the due-dates
    /// panel and force a notification.
    public var showDigest: Bool

    public init(markUiDate: Bool, showDigest: Bool) {
        self.markUiDate = markUiDate
        self.showDigest = showDigest
    }

    public static let none = ShellXDigestDecision(markUiDate: false, showDigest: false)
}

public enum ShellXDigestPlanner {
    /// Windows: `Ui.LastDigestDate == today → stop`. Mac (DECISIONS 02 Q-7): the date this DEVICE last showed the
    /// digest wins when it is known, so a shared-save pull from another computer that already showed today's digest
    /// (it carries `LastDigestDate = today`) cannot suppress this Mac's digest (03 W-8). Without a device record
    /// (first run of a copied folder) the Windows rule applies unchanged. Safe mode: nothing (REPO-113).
    public static func decide(uiLastDigestDate: String?, deviceDigestDate: String?, today: CivilDate,
                              safeMode: Bool) -> ShellXDigestDecision {
        guard !safeMode else { return .none }
        let t = today.iso
        let lastShown = deviceDigestDate ?? uiLastDigestDate
        return ShellXDigestDecision(markUiDate: uiLastDigestDate != t, showDigest: lastShown != t)
    }
}

/// Inputs of one reminder pass (computed by the AA side from the live store).
public struct ShellXReminderInput: Sendable, Equatable {
    public var summary: ReminderSummary
    public var crewExpiring: Int
    public var today: CivilDate
    public var uiLastDigestDate: String?
    public var deviceDigestDate: String?
    public var safeMode: Bool

    public init(summary: ReminderSummary, crewExpiring: Int, today: CivilDate, uiLastDigestDate: String?,
                deviceDigestDate: String?, safeMode: Bool = false) {
        self.summary = summary; self.crewExpiring = crewExpiring; self.today = today
        self.uiLastDigestDate = uiLastDigestDate; self.deviceDigestDate = deviceDigestDate; self.safeMode = safeMode
    }
}

/// What the AA side must do after one pass.
public struct ShellXReminderActions: Sendable, Equatable {
    /// Write `Ui.LastDigestDate = value` and `markDirty()`.
    public var setUiDigestDate: String?
    /// Record `value` as this device's digest date for the active data file.
    public var setDeviceDigestDate: String?
    /// Open (or refresh) the floating due-dates panel (REPO-113).
    public var openDuePanel: Bool
    /// Post `"AA — due soon"` with this body (REPO-112), replacing the previous notification (`aa.reminder`).
    public var notificationBody: String?
    /// Dock badge (DECISIONS Q-13): the overdue count when > 0, else nil (cleared).
    public var dockBadge: String?
    /// MenuBarExtra headline: `Headline()` plus the crew suffix (03 §6.8).
    public var headline: String
    /// Run W-VESSEL's work-order digest (ARCH §9.3: on every pass of the cadence).
    public var runWorkOrderDigest: Bool

    public init(setUiDigestDate: String? = nil, setDeviceDigestDate: String? = nil, openDuePanel: Bool = false,
                notificationBody: String? = nil, dockBadge: String? = nil, headline: String = "",
                runWorkOrderDigest: Bool = true) {
        self.setUiDigestDate = setUiDigestDate; self.setDeviceDigestDate = setDeviceDigestDate
        self.openDuePanel = openDuePanel; self.notificationBody = notificationBody; self.dockBadge = dockBadge
        self.headline = headline; self.runWorkOrderDigest = runWorkOrderDigest
    }
}

/// The reminder state machine of 03 SHELL-131/132 and 02 REPO-112/113: the in-memory dedup key (`_lastReminderKey`)
/// and the per-pass plan. Pure apart from its own key; the clock and the store stay on the AA side.
public struct ShellXReminderEngine: Sendable, Equatable {
    /// `"{today:yyyy-MM-dd}|{Overdue}|{DueToday}|{DueWeek}|{crew}"` of the last notification (nil = none / reset).
    public private(set) var lastKey: String?

    public init(lastKey: String? = nil) { self.lastKey = lastKey }

    /// `CheckReminders(force)`: nothing due and no crew → reset the key, no notification; an unchanged key without
    /// `force` → no notification; otherwise the key is remembered and the body returned.
    @MainActor public mutating func check(_ summary: ReminderSummary, crewExpiring crew: Int, today: CivilDate,
                               force: Bool) -> String? {
        guard summary.any || crew > 0 else {
            lastKey = nil
            return nil
        }
        let key = ReminderService.dedupKey(summary, crewExpiring: crew, today: today)
        if !force && key == lastKey { return nil }
        lastKey = key
        return ReminderService.notificationBody(summary, crewExpiring: crew)
    }

    /// One pass for `reason`: the digest (launch / day change / wake) followed by the regular check, exactly the
    /// Windows order (`ShowDailyDigestIfDue(); CheckReminders(false)`), plus the Mac surfaces (badge, headline).
    @MainActor public mutating func run(_ reason: ShellXReminderReason, _ input: ShellXReminderInput) -> ShellXReminderActions {
        var actions = ShellXReminderActions(headline: ShellXReminderEngine.headline(input.summary,
                                                                                   crewExpiring: input.crewExpiring))
        actions.dockBadge = input.summary.overdue > 0 ? String(input.summary.overdue) : nil
        guard !input.safeMode else {
            actions.runWorkOrderDigest = false
            return actions
        }
        var forcedBody: String?
        if reason.includesDigest {
            let d = ShellXDigestPlanner.decide(uiLastDigestDate: input.uiLastDigestDate,
                                               deviceDigestDate: input.deviceDigestDate, today: input.today,
                                               safeMode: input.safeMode)
            if d.markUiDate { actions.setUiDigestDate = input.today.iso }
            if d.showDigest {
                actions.setDeviceDigestDate = input.today.iso
                if input.summary.any || input.crewExpiring > 0 {
                    actions.openDuePanel = true
                    forcedBody = check(input.summary, crewExpiring: input.crewExpiring, today: input.today, force: true)
                }
            }
        }
        let regular = check(input.summary, crewExpiring: input.crewExpiring, today: input.today, force: false)
        actions.notificationBody = forcedBody ?? regular
        return actions
    }

    /// MenuBarExtra / status headline: `Headline()` + `"  ·  {crew} crew contract(s) expiring"` when crew > 0.
    @MainActor public static func headline(_ s: ReminderSummary, crewExpiring: Int) -> String {
        ReminderService.notificationBody(s, crewExpiring: crewExpiring)
    }
}

/// Per-device digest dates (DECISIONS 02 Q-7), one per active data file, in `MacPreferences`
/// (`aa.shellx.digestDates`, never in data.json or settings.json). Keeps the 32 most recently used files.
public struct ShellXDeviceDigestStore: Sendable {
    public static let key = MacPreferences.Key("aa.shellx.digestDates")
    public static let capacity = 32

    private let prefs: MacPreferences

    public init(prefs: MacPreferences = .shared) { self.prefs = prefs }

    private struct Entry: Codable, Equatable { var file: String; var date: String }

    private func load() -> [Entry] { prefs.codable(ShellXDeviceDigestStore.key, as: [Entry].self) ?? [] }

    /// The date this device last showed the digest for `dataFile` (nil = never).
    public func date(for dataFile: URL) -> String? {
        let k = ShellXDeviceDigestStore.fileKey(dataFile)
        return load().first { $0.file == k }?.date
    }

    public func record(_ date: String, for dataFile: URL) {
        let k = ShellXDeviceDigestStore.fileKey(dataFile)
        var entries = load().filter { $0.file != k }
        entries.insert(Entry(file: k, date: date), at: 0)
        if entries.count > ShellXDeviceDigestStore.capacity {
            entries.removeLast(entries.count - ShellXDeviceDigestStore.capacity)
        }
        prefs.setCodable(entries, ShellXDeviceDigestStore.key)
    }

    /// The canonical key of a data file (standardised absolute path; case-folded like the external-file lock).
    public static func fileKey(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }
}
