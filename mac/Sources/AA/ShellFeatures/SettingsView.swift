// Spec: 03 §6.4 (AA ▸ Settings… — a Settings scene exposing the same settings as the menus: identity, appearance,
//       shortcut bar, password, encryption, shared file, text-only, Drive, Gemini key; the menu items stay),
//       DECISIONS 03 Q-2 (System / Light / Dark), Q-4 (MenuBarExtra toggle), 10 Q4 (path mappings in Settings ▸ File
//       Links), 12 (Gemini key in Settings ▸ AI); ARCHITECTURE.md §7.3 (`SettingsTab`, `requestedSettingsTab`), §7.7
//       (tabs embedding `DriveSettingsSection()`, `PathMappingSettingsView()`, `GeminiKeySettingsSection()`).
import AppKit
import SwiftUI
import AACore

/// AA ▸ Settings… (⌘,): General, Security, Sync, File Links and AI.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: SettingsTab = ShellXSettingsTabMemory.initial

    var body: some View {
        TabView(selection: $tab) {
            ShellXSettingsGeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShellXSettingsSecurityTab()
                .tabItem { Label("Security", systemImage: "lock.shield") }
                .tag(SettingsTab.security)
            ShellXSettingsSyncTab()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.sync)
            ShellXSettingsFileLinksTab()
                .tabItem { Label("File Links", systemImage: "link") }
                .tag(SettingsTab.fileLinks)
            ShellXSettingsAITab()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
        }
        // Settings is chrome: native controls keep the system font (ARCH §8.3); paths stay monospaced.
        .font(.system(size: AAType.body))
        .onAppear { consumeRequest() }
        .onChange(of: env.requestedSettingsTab) { _, _ in consumeRequest() }
        .onChange(of: tab) { _, t in ShellXSettingsTabMemory.remember(t) }
    }

    /// `env.open(.settings(tab:))` selects the requested tab (then forgets the request).
    private func consumeRequest() {
        guard let requested = env.requestedSettingsTab else { return }
        withAnimation(.snappy) { tab = requested }
        env.requestedSettingsTab = nil
    }
}

/// The last tab shown (per Mac, `aa.shellx.settingsTab`); DEBUG snapshot runs may force one with `AA_SETTINGS_TAB`.
enum ShellXSettingsTabMemory {
    static let key = MacPreferences.Key("aa.shellx.settingsTab")

    static var initial: SettingsTab {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["AA_SETTINGS_TAB"], let t = SettingsTab(rawValue: forced) {
            return t
        }
        #endif
        return MacPreferences.shared.string(key).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    static func remember(_ tab: SettingsTab) { MacPreferences.shared.set(tab.rawValue, key) }
}
