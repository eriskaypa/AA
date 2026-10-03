// Spec: ARCHITECTURE.md §9.6 (F3's own debug sheets: the shared dialogs of §7.5, the tab-colours sheet and a design
//       system gallery of §8.6), OWNERSHIP F3 acceptance ("shared dialogs demo sheets registered in the snapshot
//       registry").
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerF3() {
        register("f3.prompt") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(
                title: "App identity",
                prompt: "Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save:",
                initial: "BW Pavilion Aranda",
                helpText: "Leave blank to use this Mac's name (\(SettingsStore.defaultIdentity())).")) { _ in })
        }
        register("f3.prompt-secure") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(
                title: "Gemini API key",
                prompt: "Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):",
                initial: "AIzaExampleKey", isSecure: true,
                helpText: "Leave blank and click OK to remove the key.")) { _ in })
        }
        register("f3.date-prompt") { _ in
            AnyView(DatePromptSheet(request: DatePromptRequest(
                title: "Set deadline", prompt: "Apply one deadline to 3 selected items:",
                initial: NetDateTime(year: 2026, month: 10, day: 14, kind: .unspecified))) { _ in })
        }
        register("f3.item-picker") { _ in
            let rows = ["[Equipment] Main engine", "[Equipment] Cargo pump 1", "[Equipment] Cargo pump 2",
                        "[Task] Check purifier", "[Task] Calibrate gas detectors", "[Procedure] Bunkering checklist",
                        "[Procedure] Enclosed space entry", "[Vessel] BW Pavilion Aranda"]
            return AnyView(ItemPickerSheet(prompt: "Pick related items", displays: rows, preselected: [1, 5],
                                           single: false, candidateOrder: false) { _ in })
        }
        register("f3.item-picker-single") { _ in
            AnyView(ItemPickerSheet(prompt: "Move 'Main engine' to group",
                                    displays: ["(Ungrouped)", "Engine room", "Deck", "Cargo", "Safety"],
                                    preselected: [], single: true, candidateOrder: false) { _ in })
        }
        register("f3.password-set") { _ in AnyView(PasswordSheet(mode: .setNew) { _ in }) }
        register("f3.password-change") { _ in AnyView(PasswordSheet(mode: .changeExisting) { _ in }) }
        register("f3.password-unlock") { _ in
            AnyView(PasswordSheet(mode: .unlock(prompt: "Enter the app password to unlock locked containers:")) { _ in })
        }
        register("f3.tab-colors") { _ in AnyView(TabColorsSheet(dismiss: {})) }
        register("f3.design") { _ in AnyView(ShellDesignGallery()) }
    }
}

/// The design system at a glance (tokens, type, components) — a debug-only sheet for visual verification.
struct ShellDesignGallery: View {
    @State private var search = "pump"
    @State private var date: NetDateTime? = NetDateTime(year: 2026, month: 10, day: 2, kind: .unspecified)
    @State private var noDate: NetDateTime?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AASpacing.l) {
                Text("AA design system").font(.aaMono(AAType.title, weight: .bold))
                AASectionHeader(title: "Tokens", count: 14)
                HStack(spacing: AASpacing.s) {
                    ForEach(Array(tokenColors.enumerated()), id: \.offset) { _, t in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: AARadius.control).fill(t.1)
                                .overlay(RoundedRectangle(cornerRadius: AARadius.control).strokeBorder(AAColor.border))
                                .frame(width: 44, height: 28)
                            Text(t.0).font(.system(size: 9)).foregroundStyle(AAColor.muted)
                        }
                    }
                }
                AASectionHeader(title: "Kinds")
                HStack {
                    AAKindBadge(kind: .equipment); AAKindBadge(kind: .task); AAKindBadge(kind: .procedure)
                    AAKindBadge(kind: .vessel)
                    AAStatusCapsule(text: "Shared synced 14:05", symbol: "link", color: AAColor.Status.sharedOK)
                    AAStatusCapsule(text: "Shared save OFFLINE since 14:05 — retrying", symbol: "exclamationmark.triangle.fill",
                                    color: AAColor.Status.danger)
                }
                AASectionHeader(title: "Controls")
                HStack(spacing: AASpacing.s) {
                    Button("Save") {}.aaProminent()
                    Button("Edit…") {}.aaToolbarButton()
                    Button("Cancel") {}
                    AASearchField(text: $search, prompt: "Search…").frame(width: 200)
                }
                HStack(spacing: AASpacing.l) {
                    OptionalDatePicker("Deadline", value: $date)
                    OptionalDatePicker("Start", value: $noDate)
                }
                AABanner(style: .danger, text: "Read-only safe mode — the data file couldn't be read; nothing will be saved.")
                AABanner(style: .warning, text: "This settings file came from Windows — choose the shared save file for this Mac.",
                         actions: [AABannerAction(title: "Choose…", isProminent: true) {}, AABannerAction(title: "Dismiss") {}])
                HStack(alignment: .top, spacing: AASpacing.m) {
                    AACard {
                        VStack(alignment: .leading, spacing: 6) {
                            AAStrikeText("Check purifier", struck: true)
                            AAStrikeText("Calibrate gas detectors", struck: false)
                            AAMonoText("2026-10-02 14:05")
                            AAHelpText("Muted help text wraps across lines when the card is narrow enough.")
                        }
                    }
                    HStack(spacing: 6) {
                        AAColorSwatch(color: nil)
                        AAColorSwatch(color: AAColor.color(ARGB(r: 0x1E, g: 0x88, b: 0xE5)))
                        AAColorSwatch(color: AAColor.color(ARGB(r: 0xFD, g: 0xD8, b: 0x35)))
                    }
                }
                AAEmptyState(title: "No tasks yet", symbol: "checklist",
                             message: "Click “+ New” to add a task, or ⌘N for the quick-work window.")
                    .frame(height: 180)
            }
            .padding(AASpacing.xl)
        }
        .frame(width: 760, height: 720)
        .background(AAColor.bg)
        .aaSheet(.closeType)
    }

    private var tokenColors: [(String, Color)] {
        [("bg", AAColor.bg), ("panel", AAColor.panel), ("panelAlt", AAColor.panelAlt), ("accent", AAColor.accent),
         ("fg", AAColor.fg), ("muted", AAColor.muted), ("border", AAColor.border), ("hover", AAColor.hover),
         ("selBg", AAColor.selectionBg), ("tint", AAColor.tint), ("paper", AAColor.editorPaper),
         ("danger", AAColor.Status.danger), ("ok", AAColor.Status.ok), ("due", AAColor.Status.dueSoon)]
    }
}
#endif
