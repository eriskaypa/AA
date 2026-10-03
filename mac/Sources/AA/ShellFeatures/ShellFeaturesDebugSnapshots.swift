// Spec: ARCHITECTURE.md §9.6 (each UI owner registers its sheets, ids "<owner>.<name>"). W-SHELL's windows (Settings,
//       About, Keyboard Shortcuts) are scenes the hook renders directly (`--snapshot settings|about|shortcuts`; DEBUG
//       runs pick the Settings tab with `AA_SETTINGS_TAB=<general|security|sync|fileLinks|ai>`); the sheets below are
//       the W-SHELL prompts and every Settings tab presented as a sheet on the main window, in the Settings scene's own
//       system-font chrome (`shellXSettingsChrome`), so the sheets look like the real window.
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_SHELL() {
        register("w-shell.identity-prompt") { env in
            AnyView(TextPromptSheet(request: TextPromptRequest(
                title: ShellXText.identityTitle, prompt: ShellXText.identityPrompt, initial: env.settings.appIdentity,
                helpText: ShellXText.identityHelp(defaultName: SettingsStore.defaultIdentity()))) { _ in })
        }
        register("w-shell.settings.general") { _ in AnyView(ShellXSettingsGeneralTab().shellXSettingsChrome()) }
        register("w-shell.settings.security") { _ in AnyView(ShellXSettingsSecurityTab().shellXSettingsChrome()) }
        register("w-shell.settings.sync") { _ in AnyView(ShellXSettingsSyncTab().shellXSettingsChrome()) }
        register("w-shell.settings.file-links") { _ in AnyView(ShellXSettingsFileLinksTab().shellXSettingsChrome()) }
        register("w-shell.settings.ai") { _ in AnyView(ShellXSettingsAITab().shellXSettingsChrome()) }
        register("w-shell.about") { _ in AnyView(AboutView()) }
    }
}
#endif
