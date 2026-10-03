// Spec: ARCHITECTURE.md §9.6 (W-CONT debug sheets for the snapshot hook: ids "w-cont.<name>"), OWNERSHIP W-CONT
//       acceptance (snapshots of the editor in both appearances). The previews build the attributed text directly so
//       the format bar, paper, lists, table, link and lock look can be checked before W-RICH's reader is merged.
import AppKit
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_CONT() {
        register("w-cont.editor") { _ in
            AnyView(EditorPreviewHost(width: 920, height: 640, text: EditorPreviewText.sample(),
                                      selection: NSRange(location: 52, length: 11)))
        }
        register("w-cont.editor-narrow") { _ in
            AnyView(EditorPreviewHost(width: 560, height: 520, text: EditorPreviewText.sample(),
                                      selection: NSRange(location: 0, length: 0)))
        }
        register("w-cont.editor-withheld") { _ in
            let raw = "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Unclosed"
            return AnyView(EditorPreviewHost(width: 760, height: 360,
                                             text: NSAttributedString(string: raw, attributes: EditorFormatting.defaultTypingAttributes()),
                                             selection: NSRange(location: 0, length: 0), withheld: .unparseable))
        }
        register("w-cont.editor-legacy") { _ in
            AnyView(EditorPreviewHost(width: 760, height: 360, text: NSAttributedString(),
                                      selection: NSRange(location: 0, length: 0), withheld: .legacyLocked))
        }
        register("w-cont.editor-notice") { _ in
            AnyView(EditorPreviewHost(width: 760, height: 420, text: EditorPreviewText.sample(),
                                      selection: NSRange(location: 0, length: 0),
                                      notice: EditorNotice(style: .warning, text: EditorLocking.hintText)))
        }
        register("w-cont.container") { env in
            // The real view on the first equipment item's container (file bank included).
            guard let item = env.store.data.equipment.first else {
                return AnyView(AAEmptyState(title: "No equipment in the fixture", symbol: "doc.richtext"))
            }
            return AnyView(ContainerEditorView(container: item.container,
                                               context: ContainerEditorContext(title: item.name, host: .mainPane(.equipment)))
                .id(ObjectIdentifier(item.container))
                .frame(width: 920, height: 680))
        }
        register("w-cont.insert-saved-list") { env in
            AnyView(EditorInsertSavedListSheet(store: env.store) { _ in })
        }
        register("w-cont.insert-link") { _ in
            AnyView(EditorInsertLinkSheet(initial: "https://www.imo.org") { _ in })
        }
        register("w-cont.insert-link-invalid") { _ in
            AnyView(EditorInsertLinkSheet(initial: "https://") { _ in })
        }
        register("w-cont.palettes") { _ in
            AnyView(HStack(alignment: .top, spacing: 16) {
                EditorColorPalette(kind: .text) { _ in }.background(AAColor.panel).border(AAColor.border)
                EditorColorPalette(kind: .highlight) { _ in }.background(AAColor.panel).border(AAColor.border)
                EditorTableGrid(pick: { _, _ in }, custom: {}).background(AAColor.panel).border(AAColor.border)
            }
            .padding(16))
        }
    }
}

/// A sheet-sized editor pane showing preview text (never bound to data).
struct EditorPreviewHost: View {
    let width: CGFloat
    let height: CGFloat
    let text: NSAttributedString
    let selection: NSRange
    var withheld: EditorWithheldReason?
    var notice: EditorNotice?
    @State private var controller = EditorController()

    var body: some View {
        EditorPane(controller: controller, title: "Preview")
            .frame(width: width, height: height)
            .padding(12)
            .onAppear {
                controller.showPreview(text, selection: selection, withheld: withheld, notice: notice)
            }
    }
}

/// Realistic container notes built the way the XAML reader projects them (TextKit 1 lists with marker text, a table,
/// a link, a lock).
@MainActor enum EditorPreviewText {
    static func sample() -> NSAttributedString {
        let base = EditorFormatting.defaultTypingAttributes(paragraphStyle: EditorController.defaultParagraphStyle())
        let out = NSMutableAttributedString()
        func add(_ s: String, _ tweak: (inout [NSAttributedString.Key: Any]) -> Void = { _ in }) {
            var a = base
            tweak(&a)
            out.append(NSAttributedString(string: s, attributes: a))
        }
        add("Main engine — lube oil purifier\n") { a in
            a[.font] = EditorFormatting.font(EditorFormatting.defaultFont(size: 18), bold: true)
        }
        add("Check the ")
        add("main engine") { $0[.font] = EditorFormatting.font(EditorFormatting.defaultFont(), bold: true) }
        add(" sump level before starting the purifier. Sludge discharge interval ")
        add("every 2 h") { a in
            a[.backgroundColor] = NSColor(srgbRed: 1, green: 0.96, blue: 0.62, alpha: 1)
        }
        add("; feed temperature ")
        add("90 °C") { a in a[.foregroundColor] = NSColor(srgbRed: 0.75, green: 0, blue: 0, alpha: 1) }
        add(".\n")
        add("Operating pressure: ")
        add("7.5 bar — do not change") { a in a[.backgroundColor] = EditorLocking.sentinelColor }
        add(" (class requirement).\n")
        // Bulleted list (disc) with one nested circle item.
        let disc = NSTextList(markerFormat: .disc, options: 0)
        let circle = NSTextList(markerFormat: .circle, options: 0)
        func item(_ text: String, lists: [NSTextList], marker: String) {
            let p = NSMutableParagraphStyle()
            let indent = CGFloat(lists.count) * 24
            p.textLists = lists
            p.headIndent = indent
            p.firstLineHeadIndent = indent - 20
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent - 16), NSTextTab(textAlignment: .left, location: indent)]
            p.defaultTabInterval = 24
            p.paragraphSpacing = 2
            var m = base
            m[.paragraphStyle] = p
            m[.aaListMarker] = true
            out.append(NSAttributedString(string: "\t\(marker)\t", attributes: m))
            var a = base
            a[.paragraphStyle] = p
            out.append(NSAttributedString(string: text + "\n", attributes: a))
        }
        item("Isolate the purifier and open the bowl", lists: [disc], marker: "•")
        item("Clean the disc stack in kerosene", lists: [disc, circle], marker: "◦")
        item("Renew the O-rings (spares: store B-12)", lists: [disc], marker: "•")
        let decimal = NSTextList(markerFormat: .decimal, options: 0)
        item("Record running hours in the PMS", lists: [decimal], marker: "1.")
        item("Sign off the work order", lists: [decimal], marker: "2.")
        add("Manual: ")
        add("https://www.alfalaval.com/") { a in
            a = EditorLinkRules.linkAttributes(a, url: "https://www.alfalaval.com/", linkColor: EditorLinkRules.editorLinkColor)
        }
        add("\n")
        let table = EditorTableBuilder.makeTable(rows: 3, columns: 3, base: EditorFormatting.plainBaseAttributes(from: base))
        let t = NSMutableAttributedString(attributedString: table)
        let cells = ["Part", "Interval", "Last done", "Bowl seals", "4 000 h", "2026-08-14", "Disc stack", "8 000 h", "2026-03-02"]
        var loc = 0
        for c in cells {
            let attrs = t.attributes(at: loc, effectiveRange: nil)
            t.insert(NSAttributedString(string: c, attributes: attrs), at: loc)
            loc += c.utf16.count + 1
        }
        out.append(t)
        add("Typed after the table. Boundaries of locked text stay editable.\n")
        return out
    }
}
