// Spec: 04 HIER-140 (persistence triggers: MarkDirty / Save / Flush), §8 Q-26 (a failed Save shows "Save failed" and
//       keeps the data dirty instead of crashing), HIER-130/131 (prompt and picker through F3's presenter),
//       HIER-M01 (drag payload), ARCHITECTURE.md §7.5, §9.1, §9.4 (internal drag payloads carry ids only).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// Persistence calls of the hierarchy pages, with the Q-26 error handling.
@MainActor
enum HierPersist {
    /// **Save** (immediate, confirmed). A failure keeps the model dirty and shows "Save failed".
    static func save(_ env: AppEnvironment, dialogs: DialogPresenter) {
        do {
            try env.store.save()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in await dialogs.error(HierText.saveFailedTitle, message) }
        }
    }

    /// **MarkDirty** (debounced autosave).
    static func markDirty(_ env: AppEnvironment) { env.store.markDirty() }

    /// **Flush** = MarkDirty + FlushIfDirty.
    static func flush(_ env: AppEnvironment, dialogs: DialogPresenter) {
        env.store.markDirty()
        do {
            try env.store.flushIfDirty()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in await dialogs.error(HierText.saveFailedTitle, message) }
        }
    }
}

/// Shared prompt / picker helpers.
@MainActor
enum HierDialogs {
    /// HIER-130 prompt; nil = cancelled. The raw text is returned (callers test blankness).
    static func prompt(_ dialogs: DialogPresenter, title: String, label: String, initial: String = "") async -> String? {
        switch await dialogs.prompt(TextPromptRequest(title: title, prompt: label, initial: initial)) {
        case .ok(let text): return text
        case .cancelled: return nil
        }
    }
}

/// HIER-M01 / ARCH §9.4: sidebar rows dragged onto a group header carry only ids (`com.eriskay.aa.item-ref`).
struct HierItemDrag: Codable, Transferable {
    var ids: [UUID]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .aaItemRef)
    }
}

/// A labelled form row (Windows' fixed label column, right-aligned and muted on the Mac).
struct HierFormRow<Content: View>: View {
    let label: String
    var width: CGFloat = 150
    var help: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text(label)
                .foregroundStyle(AAColor.muted)
                .frame(width: width, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
        .help(help ?? "")
    }
}

/// A titled block of the detail tabs (bold heading, optional trailing buttons, content).
struct HierBlock<Trailing: View, Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack(alignment: .center, spacing: AASpacing.s) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(AAColor.muted).imageScale(.small)
                }
                Text(title).font(.aaMono(AAType.body, weight: .bold)).foregroundStyle(AAColor.accent)
                Spacer(minLength: AASpacing.s)
                trailing()
            }
            content()
        }
    }
}

/// Finds and focuses an AppKit field that sits next to a SwiftUI anchor (the sidebar's search field, ⌥⌘F).
@MainActor final class HierFieldLocator {
    weak var anchor: NSView?

    /// The `NSSearchField` whose window frame overlaps the anchor's.
    var field: NSSearchField? {
        guard let anchor, let window = anchor.window, let root = window.contentView else { return nil }
        let target = anchor.convert(anchor.bounds, to: nil)
        var found: NSSearchField?
        func walk(_ v: NSView) {
            if found != nil { return }
            if let f = v as? NSSearchField, f.convert(f.bounds, to: nil).intersects(target) { found = f; return }
            for s in v.subviews { walk(s) }
        }
        walk(root)
        return found
    }

    func focus() {
        guard let f = field, let w = f.window else { return }
        w.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }

    var isFocused: Bool {
        guard let f = field, let editor = f.window?.firstResponder as? NSTextView else { return false }
        return editor.delegate === f
    }
}

struct HierFieldAnchor: NSViewRepresentable {
    let locator: HierFieldLocator
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        locator.anchor = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { locator.anchor = nsView }
}
