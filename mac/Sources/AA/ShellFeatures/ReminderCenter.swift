// Spec: 03 SHELL-130 (tray → MenuBarExtra), SHELL-131 (30-minute reminder check, dedup key, "AA — due soon"),
//       SHELL-132 (daily digest at launch; LastDigestDate + MarkDirty; due-dates window + forced notification),
//       SHELL-133 (crew expiries in the reminder count), SHELL-190 (translocation sheet once per launch, REQ-F3-02),
//       SHELL-196 / Q-16 (EncryptLocalData that came from another computer), §6.8, §1.3 step 18–19; 02 REPO-112,
//       REPO-113; 09 CREW-092; DECISIONS 02 Q-7 (day rollover, per-device digest date), Q-13 (Dock badge,
//       MenuBarExtra), 10 Q7 (work-order notifications on the same cadence); ARCHITECTURE.md §7.7, §9.3.
import AppKit
import SwiftUI
import AACore

enum DigestReason { case launch, timer, dayChanged, wake }

/// Reminders, Dock badge, MenuBarExtra headline and the daily digest. F3 starts it once the main window shows data
/// (editor instances only) and stops it on quit; it never runs in safe mode or in a read-only instance.
@MainActor @Observable
final class ReminderCenter {
    static let shared = ReminderCenter()

    /// The MenuBarExtra headline: `Headline()` + crew suffix ("Nothing due." when idle).
    private(set) var headline = "Nothing due."
    private(set) var summary = ReminderSummary()
    private(set) var crewExpiring = 0
    private(set) var isRunning = false
    /// When the last pass ran (MenuBarExtra footnote).
    private(set) var lastCheck: Date?

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private var engine = ShellXReminderEngine()
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var subscriptions: [EventSubscription] = []
    @ObservationIgnored private var translocationShown = false
    @ObservationIgnored private let digestStore = ShellXDeviceDigestStore()
    @ObservationIgnored private let menuBarGuard = ShellXMenuBarGuardStore()
    /// Bumped by `stop()` so a pending menu-bar observation from an earlier run never records anything.
    @ObservationIgnored private var menuBarWatchGeneration = 0

    /// The 30-minute reminder cadence (03 §3.13).
    static let interval: Duration = .seconds(30 * 60)

    // MARK: Start / stop

    func start(env: AppEnvironment) {
        stop()
        guard !env.isSafeMode, !env.isReadOnlyInstance else { return }
        self.env = env
        isRunning = true
        let smoke = LaunchCoordinator.shared.options.smokeTest

        // SHELL-196 / Q-16: never encrypt a folder for this Mac only without asking.
        if !smoke, ShellXDataFlows.foreignEncryptionPromptNeeded(env.dataStore) {
            env.store.pauseWrites(reason: .other("encryption-guard"))
            Task { @MainActor in await self.askForeignEncryption(env) }
        }
        // SHELL-190: once per launch, after the main window appeared; never in smoke runs.
        if env.isTranslocated, !translocationShown, !smoke {
            translocationShown = true
            Task { @MainActor in await env.mainDialogs.info(ShellXText.translocationTitle, ShellXText.translocationMessage) }
        }

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ReminderCenter.interval)
                guard !Task.isCancelled, let self else { return }
                self.runDigest(reason: .timer)
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runDigest(reason: .dayChanged) }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runDigest(reason: .wake) }
        })
        // The badge and headline follow the data between passes (no notifications from these).
        subscriptions.append(env.store.saved.subscribe { [weak self] in self?.refreshSurfaces() })
        subscriptions.append(env.store.dataReplaced.subscribe { [weak self] _ in self?.refreshSurfaces() })
        if !smoke, !LaunchCoordinator.shared.snapshotMode { startMenuBarGuard() }

        runDigest(reason: .launch)
    }

    func stop() {
        menuBarWatchGeneration += 1
        timerTask?.cancel()
        timerTask = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers.removeAll()
        workspaceObservers.removeAll()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        isRunning = false
    }

    // MARK: Passes

    /// One reminder pass (03 SHELL-131/132, ARCH §9.3): digest (launch / day change / wake), the deduplicated
    /// reminder notification, Dock badge, MenuBarExtra headline, then W-VESSEL's work-order digest.
    func runDigest(reason: DigestReason) {
        guard let env, isRunning, env.mainLoaded, !env.isSafeMode, !env.isReadOnlyInstance else { return }
        let store = env.store
        let today = env.clock.today()
        let dataFile = env.dataStore.currentDataFile
        let smoke = LaunchCoordinator.shared.options.smokeTest
        let s = ReminderService.compute(store: store, today: today)
        let crew = CrewExpiry.expiringCount(store.data.crew, today: today)
        let input = ShellXReminderInput(summary: s, crewExpiring: crew, today: today,
                                        uiLastDigestDate: store.data.ui.lastDigestDate,
                                        deviceDigestDate: smoke ? nil : digestStore.date(for: dataFile),
                                        safeMode: env.isSafeMode)
        let actions = engine.run(reason.shellX, input)

        if let date = actions.setUiDigestDate {
            store.data.ui.lastDigestDate = date
            store.markDirty()
        }
        if let date = actions.setDeviceDigestDate, !smoke { digestStore.record(date, for: dataFile) }
        if actions.openDuePanel { env.open(.dueDates) }
        if let body = actions.notificationBody {
            NotificationCenterBridge.post(id: Identifiers.reminderNotificationID, title: ShellXText.reminderTitle,
                                          body: body, onClick: .dueDates)
        }
        apply(actions, summary: s, crew: crew)
        if actions.runWorkOrderDigest { WorkOrderNotifications.runDigest(env: env, today: today) }
    }

    /// Badge and headline only (after saves and reloads).
    private func refreshSurfaces() {
        guard let env, isRunning, env.mainLoaded else { return }
        let today = env.clock.today()
        let s = ReminderService.compute(store: env.store, today: today)
        let crew = CrewExpiry.expiringCount(env.store.data.crew, today: today)
        apply(ShellXReminderActions(dockBadge: s.overdue > 0 ? String(s.overdue) : nil,
                                    headline: ShellXReminderEngine.headline(s, crewExpiring: crew)),
              summary: s, crew: crew)
    }

    private func apply(_ actions: ShellXReminderActions, summary s: ReminderSummary, crew: Int) {
        summary = s
        crewExpiring = crew
        if headline != actions.headline { headline = actions.headline }
        lastCheck = Date()
        NSApp.dockTile.badgeLabel = actions.dockBadge
    }

    // MARK: MenuBarExtra preference guard (REQ-W-SHELL-02 workaround, DECISIONS 03 Q-4)

    /// The scene's `isInserted` binding writes `aa.menuBarExtra = false` whenever SwiftUI pushes "not inserted" back
    /// while the item is meant to be hidden (splash, login). Main phase: restore it unless the user hid the item on
    /// purpose, then record every later change (Settings toggle, ⌘-drag out of the menu bar) as the user's choice.
    private func startMenuBarGuard() {
        let coordinator = LaunchCoordinator.shared
        if ShellXMenuBarPolicy.shouldRestore(enabled: coordinator.menuBarExtraEnabled,
                                             userHidden: menuBarGuard.userHidden) {
            coordinator.setMenuBarExtra(true)
        }
        observeMenuBarPreference(generation: menuBarWatchGeneration)
    }

    private func observeMenuBarPreference(generation: Int) {
        let coordinator = LaunchCoordinator.shared
        withObservationTracking {
            _ = coordinator.menuBarExtraEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, generation == self.menuBarWatchGeneration,
                      coordinator.phase == .main else { return }
                self.menuBarGuard.record(enabled: coordinator.menuBarExtraEnabled)
                self.observeMenuBarPreference(generation: generation)
            }
        }
    }

    // MARK: SHELL-196 guard

    private func askForeignEncryption(_ env: AppEnvironment) async {
        let spec = AlertSpec(title: ShellXText.encryptTitle, message: ShellXText.encryptForeignMessage,
                             style: .warning,
                             buttons: [AlertButton(title: ShellXText.encryptButton, role: .default),
                                       AlertButton(title: ShellXText.keepPlaintextButton, role: .cancel)])
        let choice = await env.mainDialogs.alert(spec)
        if choice != 0 {
            env.settings.setEncryptLocalData(false)
            env.status.post(ShellXText.encryptedOff)
            if env.settings.lastWriteRefused { env.status.post(SettingsStore.unreadableStatus) }
        }
        if env.store.writePauseReason == .other("encryption-guard") { env.store.resumeWrites() }
    }
}

private extension DigestReason {
    var shellX: ShellXReminderReason {
        switch self {
        case .launch: return .launch
        case .timer: return .timer
        case .dayChanged: return .dayChanged
        case .wake: return .wake
        }
    }
}
