// Spec: 06 BUILD-130/131 + Addendum BUILD-136…147 (one shared prompt / picker — F3's components, callers trim), 06
//       §6.2 (Replace / Append / Cancel buttons keep the Windows sentence; destructive confirmations), BUILD-A20
//       (Save / FlushIfDirty; builders never swallow save errors — the Mac reports them, ARCH §9.1), 07 VIEW-211
//       (single-select pickers), VIEW-212 rows 4–6 and 13–14, 18–22 (this owner's picker call sites).
// Small shared helpers of the W-BUILD views: persistence calls, prompts, pickers and the three-button questions.
import AppKit
import SwiftUI
import AACore

@MainActor enum BuilderUI {
    // MARK: Persistence (06 [persist: Save] / [persist: Flush])

    /// [persist: Save] — a confirmed synchronous save; failures are reported (SHELL-001), never swallowed.
    static func save(_ env: AppEnvironment, context: String = "Saving") {
        do { try env.store.save() } catch { env.reportError(error, context: context) }
    }

    /// [persist: Flush] — `FlushIfDirty`.
    static func flush(_ env: AppEnvironment, context: String = "Saving") {
        do { try env.store.flushIfDirty() } catch { env.reportError(error, context: context) }
    }

    // MARK: Prompts and pickers

    /// The shared text prompt (BUILD-136…150). Returns the raw text on OK — possibly blank; nil on Cancel.
    static func prompt(_ dialogs: DialogPresenter, title: String, prompt: String, initial: String = "") async -> String? {
        if case .ok(let v) = await dialogs.prompt(TextPromptRequest(title: title, prompt: prompt, initial: initial)) {
            return v
        }
        return nil
    }

    /// A raw, non-blank prompt value (the 30 "blank = no-op" callers, BUILD-A24 a/b); nil otherwise.
    static func nonBlankPrompt(_ dialogs: DialogPresenter, title: String, prompt: String,
                               initial: String = "") async -> String? {
        guard let v = await Self.prompt(dialogs, title: title, prompt: prompt, initial: initial), !NetText.isBlank(v)
        else { return nil }
        return v
    }

    /// Single-select picker (VIEW-211: OK disabled until a row is chosen). Returns the chosen tag or nil.
    static func pickOne<Tag: Hashable & Sendable>(_ dialogs: DialogPresenter, prompt: String,
                                                  rows: [(display: String, tag: Tag)],
                                                  preselected: [Tag] = []) async -> Tag? {
        let req = ItemPickerRequest(prompt: prompt, rows: rows.map { ItemPickerRow(display: $0.display, tag: $0.tag) },
                                    preselected: preselected, mode: .single)
        return await dialogs.pickItems(req)?.first
    }

    /// Multi-select picker returning tags in selection order (VIEW-208/210); nil = cancelled.
    static func pickMany<Tag: Hashable & Sendable>(_ dialogs: DialogPresenter, prompt: String,
                                                   rows: [(display: String, tag: Tag)],
                                                   preselected: [Tag]) async -> [Tag]? {
        let req = ItemPickerRequest(prompt: prompt, rows: rows.map { ItemPickerRow(display: $0.display, tag: $0.tag) },
                                    preselected: preselected, mode: .multi)
        return await dialogs.pickItems(req)
    }

    // MARK: Questions

    enum Choice { case first, second, cancel }

    /// A Windows Yes/No/Cancel box rendered with explicit Mac verbs (06 §6.2): `first` ⇔ Yes, `second` ⇔ No.
    static func threeWay(_ dialogs: DialogPresenter, title: String, message: String, first: String,
                         second: String, secondDestructive: Bool = false) async -> Choice {
        let spec = AlertSpec(title: title, message: message, style: .informational,
                             buttons: [AlertButton(title: first, role: .default),
                                       AlertButton(title: second, role: secondDestructive ? .destructive : .normal),
                                       AlertButton(title: "Cancel", role: .cancel)])
        switch await dialogs.alert(spec) {
        case 0: return .first
        case 1: return .second
        default: return .cancel
        }
    }

    /// A destructive Yes/No confirmation (defaults to Cancel, 03 §6.5 C13).
    static func confirmDelete(_ dialogs: DialogPresenter, title: String, message: String,
                              confirm: String = "Delete") async -> Bool {
        await dialogs.confirm(title, message, confirm: confirm, destructive: true, defaultIsCancel: true)
    }
}

// MARK: - Shared visuals

/// The large header of every builder / editor sheet (06 §6.2: large title + secondary help text).
struct BuilderSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String = "hammer"

    var body: some View {
        HStack(alignment: .top, spacing: AASpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AAColor.tint)
                .frame(width: 34, height: 34)
                .background(AAColor.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A small labelled toolbar button with an SF Symbol (06 §6.2 button bar) and the Windows tooltip.
struct BuilderBarButton: View {
    let title: String
    let symbol: String
    var help: String? = nil
    var iconOnly = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if iconOnly {
                Image(systemName: symbol).frame(minWidth: 16)
            } else {
                Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// A captioned group box in the app's card style (used by the editors' forms and the Saved Lists detail).
struct BuilderCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(AASpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }
}

/// The orphan state shown when the item a sheet edits vanished (reload, delete elsewhere — 06 §8 R1, ARCH §2.4).
struct BuilderOrphanState: View {
    let what: String
    var body: some View {
        AAEmptyState(title: "\(what) no longer exists",
                     symbol: "exclamationmark.triangle",
                     message: "It was deleted or replaced by a reload while this window was open. Nothing was lost — "
                        + "every change was saved as you made it.")
    }
}

/// A form label column (BUILD-020 / BUILD-050: label column width 100).
struct BuilderFormLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .foregroundStyle(AAColor.muted)
            .frame(width: 112, alignment: .trailing)
    }
}
