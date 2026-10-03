// Spec: 03 §6.4 (Settings scene: identity, appearance, shortcut bar, password, Lock Now, encryption, shared file,
//       text-only, Drive, Gemini key), SHELL-065…069, 072, 101, 102, 110/111 (appearance, shortcut bar), §6.8
//       (MenuBarExtra, Q-4 toggle), §6.9 (data folder), 06 BUILD-145 B1 ("if the Settings scene has an identity field,
//       committing it blank must also reset"; "Use Mac Name" optional extra), 01 DATA-021 (safe mode refuses),
//       DATA-182 (unreadable settings status), DECISIONS 03 Q-2, Q-4; ARCHITECTURE.md §7.7 (tabs), §8 (design system).
import AppKit
import SwiftUI
import AACore

// MARK: - Shared pieces

/// A help line under a settings row (muted, wrapping).
private struct ShellXSettingsHelp: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A selectable, middle-truncated path value (kept on the row's line; the full path is in the tooltip).
private struct ShellXPathText: View {
    let path: String
    var maxWidth: CGFloat = 330
    var body: some View {
        Text(path)
            .font(.aaMono(AAType.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: maxWidth, alignment: .trailing)
            .help(path)
    }
}

/// Shown in place of data-bound controls before the main window has loaded data (login phase).
private struct ShellXSignInNotice: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        if !env.mainLoaded {
            Label(ShellXSettingsGate.signInNotice, systemImage: "person.badge.key")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

struct ShellXSettingsGeneralTab: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var identityDraft = ""
    @State private var appearance: AppearanceMode = .system
    @State private var menuBarExtra = LaunchCoordinator.shared.menuBarExtraEnabled
    @FocusState private var identityFocused: Bool

    private var defaultName: String { SettingsStore.defaultIdentity() }

    /// SHELL-004 / §6.1: before sign-in nothing here may write `settings.json` or the data folder.
    private func enabled(_ c: ShellXSettingsGate.GeneralControl) -> Bool {
        ShellXSettingsGate.isEnabled(c, mainLoaded: env.mainLoaded)
    }

    var body: some View {
        Form {
            ShellXSignInNotice()
            Section {
                LabeledContent("Name") {
                    HStack(spacing: AASpacing.s) {
                        TextField("App identity", text: $identityDraft, prompt: Text(defaultName))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)    // a Form row right-aligns field text by default
                            .focused($identityFocused)
                            .onSubmit(commitIdentity)
                            .frame(minWidth: 180)
                        Button("Use Mac Name") {
                            identityDraft = ""
                            commitIdentity()
                        }
                        .help("Reset the identity to this Mac's name (\(defaultName)).")
                    }
                    .disabled(!enabled(.appIdentity))
                }
                LabeledContent("Window title") {
                    Text(env.windowTitle).foregroundStyle(.secondary)
                }
                ShellXSettingsHelp(ShortcutRegistry.row(.setAppIdentity)?.help ?? ShellXText.identityPrompt)
            } header: {
                Text("App Identity")
            }

            Section("Appearance") {
                Picker("Appearance", selection: Binding(get: { appearance }, set: setAppearance)) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                    Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                    Label("Dark", systemImage: AASymbol.darkMode).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .disabled(!enabled(.appearance))
                ShellXSettingsHelp("Light and Dark are remembered with your data (Dark mode); System follows this Mac and leaves that setting as it is.")
                Toggle("Show the keyboard shortcut bar", isOn: Binding(
                    get: { env.store.data.ui.showShortcutBar },
                    set: { env.setShortcutBarVisible($0) }))
                    .disabled(!enabled(.shortcutBar))
            }

            Section("Menu Bar and Notifications") {
                Toggle("Show AA in the menu bar", isOn: Binding(get: { menuBarExtra }, set: { on in
                    menuBarExtra = on
                    LaunchCoordinator.shared.setMenuBarExtra(on)
                }))
                ShellXSettingsHelp("The menu bar item shows what is overdue or due today and opens the due-dates window. Reminders arrive as notifications either way.")
                LabeledContent("Notifications") {
                    Button("Notification Settings…") { ShellXSystemSettings.openNotifications() }
                        .disabled(!NotificationCenterBridge.isAvailable)
                }
            }

            Section("Data Folder") {
                LabeledContent("Folder") {
                    HStack(spacing: AASpacing.s) {
                        ShellXPathText(path: env.dataStore.appFolder.path, maxWidth: 250)
                        Button("Show in Finder") { run(.openDataFolder) }
                            .disabled(!enabled(.showDataFolder))
                    }
                }
                LabeledContent("Active data file") { ShellXPathText(path: env.dataStore.currentDataFile.path) }
                LabeledContent("AA version") {
                    Text(ShellXVersionInfo.current.versionLine).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 760)
        .onAppear {
            identityDraft = env.settings.appIdentity
            appearance = ShellAppearance.storedMode(settings: env.settings)
        }
        .onChange(of: identityFocused) { _, focused in
            if !focused, identityDraft != env.settings.appIdentity { commitIdentity() }
        }
        .onChange(of: env.settings.values.appIdentity) { _, _ in
            if !identityFocused { identityDraft = env.settings.appIdentity }
        }
    }

    /// B1: blank → this Mac's name, else trimmed; the status shows the stored value.
    private func commitIdentity() {
        guard enabled(.appIdentity) else { identityDraft = env.settings.appIdentity; return }
        let stored = ShellXDataFlows.setAppIdentity(identityDraft, settings: env.settings)
        identityDraft = stored
        env.postSettingStatus(ShellXText.identitySet(stored))
        if env.settings.lastWriteRefused { env.status.post(SettingsStore.unreadableStatus) }
    }

    private func setAppearance(_ mode: AppearanceMode) {
        guard enabled(.appearance) else { return }
        appearance = mode
        ShellAppearance.set(mode, settings: env.settings)
        env.router.darkModeChecked = ShellAppearance.isEffectivelyDark
        switch mode {
        case .dark: env.postSettingStatus(ShellStatusText.darkModeOn)
        case .light: env.postSettingStatus(ShellStatusText.darkModeOff)
        case .system: break
        }
    }

    private func run(_ c: CommandID) {
        Task { @MainActor in await ShellFlows.perform(c, env: env, dialogs: dialogs) }
    }
}

// MARK: - Security

struct ShellXSettingsSecurityTab: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var onDisk = ""

    var body: some View {
        Form {
            ShellXSignInNotice()
            Section("App Password") {
                LabeledContent("Password") {
                    Label(env.passwords.hasPassword ? "Set" : "Not set",
                          systemImage: env.passwords.hasPassword ? AASymbol.lockFill : AASymbol.unlock)
                        .foregroundStyle(env.passwords.hasPassword ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                LabeledContent("This session") {
                    Text(env.passwords.isUnlocked ? "Unlocked" : "Locked").foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(env.passwords.hasPassword ? "Change Password…" : "Set Password…") { run(.setPassword) }
                    Button("Lock Now") { run(.lockNow) }
                        .help(ShortcutRegistry.row(.lockNow)?.help ?? "")
                }
                ShellXSettingsHelp("One app password locks and unlocks every protected container and entry. Changing it asks for the current password first.")
            }
            .disabled(!env.mainLoaded)

            Section("Local Data File") {
                Toggle("Encrypt local data file (this Mac)", isOn: Binding(
                    get: { env.settings.values.encryptLocalData },
                    set: { _ in run(.encryptLocalData) }))
                ShellXSettingsHelp(ShortcutRegistry.row(.encryptLocalData)?.help ?? "")
                LabeledContent("Active data file") { ShellXPathText(path: env.dataStore.currentDataFile.path) }
                LabeledContent("On disk") { Text(onDisk).foregroundStyle(.secondary) }
            }
            .disabled(!env.mainLoaded || env.isSafeMode || env.isReadOnlyInstance)
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 470)
        .onAppear(perform: refresh)
        .onChange(of: env.settings.values.encryptLocalData) { _, _ in refresh() }
        .onChange(of: env.store.generation) { _, _ in refresh() }
    }

    private func refresh() { onDisk = ShellXDataFlows.onDiskDescription(env.dataStore) }

    private func run(_ c: CommandID) {
        Task { @MainActor in
            await ShellFlows.perform(c, env: env, dialogs: dialogs)
            refresh()
        }
    }
}

// MARK: - Sync

struct ShellXSettingsSyncTab: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    private var sharedPath: String? {
        let p = env.settings.values.sharedSaveFile
        return NetText.isBlank(p) ? nil : p
    }

    var body: some View {
        Form {
            ShellXSignInNotice()
            Section("Shared Save File") {
                LabeledContent("File") {
                    if let sharedPath { ShellXPathText(path: sharedPath) } else {
                        Text("Not set — saving locally on this Mac").foregroundStyle(.secondary)
                    }
                }
                if sharedPath != nil {
                    LabeledContent("Status") { ShellXSharedHealthCapsule(coordinator: env.sharedSave) }
                }
                HStack {
                    Spacer()
                    Button(sharedPath == nil ? "Set Shared Save File…" : "Change…") { run(.setSharedSaveFile) }
                    Button("Check Now") { run(.checkSharedSaveNow) }.disabled(sharedPath == nil)
                    Button("Stop Using…") { run(.stopSharedSaveFile) }.disabled(sharedPath == nil)
                }
                ShellXSettingsHelp(ShortcutRegistry.row(.setSharedSaveFile)?.help ?? "")
            }
            .disabled(!env.mainLoaded || env.isSafeMode || env.isReadOnlyInstance)

            Section("Exports") {
                Toggle("Export text only (no attachments)", isOn: Binding(
                    get: { env.settings.values.textOnlyExport },
                    set: { _ in run(.exportTextOnly) }))
                ShellXSettingsHelp(ShortcutRegistry.row(.exportTextOnly)?.help ?? "")
            }
            .disabled(!env.mainLoaded)

            DriveSettingsSection()
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 600)
    }

    private func run(_ c: CommandID) {
        Task { @MainActor in await ShellFlows.perform(c, env: env, dialogs: dialogs) }
    }
}

/// The shared-save state as a capsule (texts from W-PERSIST's coordinator when it provides them).
private struct ShellXSharedHealthCapsule: View {
    let coordinator: SharedSaveCoordinator

    var body: some View {
        let (text, symbol, color) = describe()
        AAStatusCapsule(text: text, symbol: symbol, color: color)
            .help(coordinator.indicatorHelp)
    }

    private func describe() -> (String, String, Color) {
        let given = coordinator.indicatorText
        switch coordinator.health {
        case .off:
            return (given.isEmpty ? "Not syncing yet" : given, "pause.circle", AAColor.Status.neutral)
        case .online(let last):
            let fallback = last.map { "Online — synced \(Self.time($0))" } ?? "Online"
            return (given.isEmpty ? fallback : given, "checkmark.circle.fill", AAColor.Status.sharedOK)
        case .offline(let since):
            return (given.isEmpty ? "Offline since \(Self.time(since))" : given, "wifi.exclamationmark",
                    AAColor.Status.danger)
        case .notSaving(let since):
            return (given.isEmpty ? "Not saving since \(Self.time(since))" : given, AASymbol.warning,
                    AAColor.Status.danger)
        }
    }

    private static func time(_ d: Date) -> String {
        NetDateTime(date: d, kind: .local, zone: .current).format(.time)
    }
}

// MARK: - File Links and AI (owners' sections)

struct ShellXSettingsFileLinksTab: View {
    var body: some View {
        PathMappingSettingsView()
            .frame(width: 640, height: 480)
    }
}

struct ShellXSettingsAITab: View {
    var body: some View {
        Form {
            GeminiKeySettingsSection()
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 360)
    }
}

// MARK: - System Settings links

enum ShellXSystemSettings {
    /// System Settings ▸ Notifications ▸ AA.
    @MainActor static func openNotifications() {
        let id = Bundle.main.bundleIdentifier ?? Identifiers.bundleID
        let candidates = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                          "x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
    }
}
