// Spec: 12 SIRE-036/037 (Tools ▸ SIRE 2.0 Export…: the export sheet on the main window; the "still loading" text when
//       the wait is dismissed), SIRE-038 + §6.9 (Tools ▸ Set Gemini API Key…: secure prompt with reveal toggle, Mac
//       wording naming the Keychain, blank clears, status `Gemini API key saved.` / `Gemini API key cleared.`; Settings ▸
//       AI section with Save / Clear), 06 BUILD-143/145 B2, BUILD-A26/A27, BUILD-148 (B2 helper line), 03 SHELL-099/100
//       (SHELL-655/656 rows); ARCHITECTURE.md §7.7 (`SireActions`, `GeminiKeySettingsSection()`).
import AppKit
import SwiftUI
import AACore

@MainActor enum SireActions {
    static let geminiPromptTitle = "Gemini API key"
    static let geminiPrompt = "Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):"
    static let geminiHelp = "Leave blank and click OK to remove the key."
    static let keySaved = "Gemini API key saved."
    static let keyCleared = "Gemini API key cleared."

    /// Tools ▸ SIRE 2.0 Export… (SHELL-655).
    static func showExportDialog(env: AppEnvironment, dialogs: DialogPresenter) async {
        env.showMainWindow()
        SireViewModel.shared.attach(env)
        var outcome = SireExportOutcome.cancelled
        await dialogs.presentSheet(.decision) { dismiss in
            SireExportSheet { o in outcome = o; dismiss() }
        }
        if outcome == .cancelledWhileLoading {
            await dialogs.info("SIRE export", "The SIRE question bank is still loading — try again in a moment.")
        }
    }

    /// Tools ▸ Set Gemini API Key… (SHELL-656, BUILD-145 B2): OK with blank clears the key.
    static func setGeminiKey(env: AppEnvironment, dialogs: DialogPresenter) async {
        env.showMainWindow()
        let store = SireGeminiKeys.store(env)
        let request = TextPromptRequest(title: geminiPromptTitle, prompt: geminiPrompt, initial: store.key() ?? "",
                                        isSecure: true, helpText: geminiHelp)
        guard case .ok(let value) = await dialogs.prompt(request) else { return }
        do {
            try store.setKey(value)
            env.status.post(NetText.isBlank(value) ? keyCleared : keySaved)
        } catch {
            await dialogs.error(geminiPromptTitle, "The key could not be stored in this Mac's Keychain (\(error)).")
        }
    }
}

/// Settings ▸ AI: the Gemini key (embedded by W-SHELL's SettingsView, typically inside a `Form`).
struct GeminiKeySettingsSection: View {
    @State private var draft = ""
    @State private var reveal = false
    @State private var hasKey = false
    @State private var message: String?
    @State private var loaded = false

    private var env: AppEnvironment? { LaunchCoordinator.shared.env }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: hasKey ? "key.fill" : "key")
                        .foregroundStyle(hasKey ? AAColor.Status.ok : AAColor.muted)
                        .contentTransition(.symbolEffect(.replace))
                    Text(hasKey ? "A Gemini API key is stored in this Mac's Keychain." : "No Gemini API key is set.")
                        .foregroundStyle(hasKey ? AAColor.fg : AAColor.muted)
                }
                Text(SireActions.geminiPrompt)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Group {
                        if reveal {
                            TextField("API key", text: $draft)
                        } else {
                            SecureField("API key", text: $draft)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { save() }
                    Toggle(isOn: $reveal) { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .toggleStyle(.button)
                        .help(reveal ? "Hide the key" : "Show the key")
                }
                HStack(spacing: 8) {
                    Button("Save") { save() }.aaProminent().disabled(env == nil)
                    Button("Clear", role: .destructive) { clear() }.disabled(env == nil || !hasKey)
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(AAColor.Status.ok)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                Text("Used by AI Suggest… on the SIRE 2.0 tab. The key is sent only to Google’s Gemini API, in a request header. Saving a blank field removes the key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Google Gemini", systemImage: "sparkles")
        }
        .onAppear(perform: refresh)
        .animation(.snappy, value: message)
    }

    private func refresh() {
        guard let env else { return }
        let store = SireGeminiKeys.store(env)
        hasKey = store.hasKey
        if !loaded { draft = store.key() ?? ""; loaded = true }
    }

    private func save() {
        guard let env else { return }
        do {
            try SireGeminiKeys.store(env).setKey(draft)
            let text = NetText.isBlank(draft) ? SireActions.keyCleared : SireActions.keySaved
            if NetText.isBlank(draft) { draft = "" } else { draft = NetText.trim(draft) }
            message = text
            env.status.post(text)
        } catch {
            message = nil
            env.reportError(error, context: "Saving the Gemini API key")
        }
        refresh()
    }

    private func clear() {
        draft = ""
        save()
    }
}
