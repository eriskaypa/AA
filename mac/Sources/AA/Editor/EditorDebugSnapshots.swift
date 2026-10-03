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
        register("w-cont.selftest") { _ in AnyView(EditorSelfTestView()) }
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

/// Drives a live controller through the AppKit paths unit tests cannot reach (lock gate in `shouldChangeText`,
/// undo of attribute edits, table/link insertion through `apply`, alignment, Tab) and shows ✓ / ✗ per step.
struct EditorSelfTestView: View {
    @State private var controller = EditorController()
    @State private var results: [(String, Bool)] = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPane(controller: controller, title: "Self-test")
                .frame(width: 560, height: 520)
            VStack(alignment: .leading, spacing: 4) {
                Text("Editor self-test").font(.system(size: AAType.body, weight: .bold))
                ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                    Label(r.0, systemImage: r.1 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(r.1 ? AAColor.Status.ok : AAColor.Status.danger)
                        .font(.system(size: AAType.small))
                }
                Spacer()
            }
            .frame(width: 330, height: 520, alignment: .topLeading)
        }
        .padding(12)
        .onAppear { results = Self.run(controller) }
    }

    @MainActor static func run(_ c: EditorController) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        func check(_ name: String, _ ok: Bool) { out.append((name, ok)) }
        let base = EditorFormatting.defaultTypingAttributes(paragraphStyle: EditorController.defaultParagraphStyle())
        let doc = NSMutableAttributedString(string: "abcDEFghi\nsecond line\n", attributes: base)
        EditorLocking.lock(doc, range: NSRange(location: 3, length: 3))
        c.showPreview(doc, selection: NSRange(location: 0, length: 0))
        let tv = c.textView
        let storage = tv.textStorage!

        tv.setSelectedRange(NSRange(location: 4, length: 0))
        tv.insertText("X", replacementRange: tv.selectedRange())
        check("typing inside a lock is blocked", storage.string.hasPrefix("abcDEFghi"))
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertText("Y", replacementRange: tv.selectedRange())
        check("typing at a lock boundary works", storage.string.hasPrefix("abcYDEFghi"))
        check("new text at the boundary is not locked", !EditorLocking.isLocked(storage, at: 3))
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        tv.deleteBackward(nil)
        check("Backspace into a lock is blocked", storage.string.hasPrefix("abcYDEFghi"))

        tv.setSelectedRange(NSRange(location: 0, length: 3))
        c.perform(.bold)
        check("Bold applies to the selection", EditorFormatting.isBold(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont))
        check("format bar reflects Bold", c.summary.bold)
        c.undo()
        check("Undo removes Bold", !EditorFormatting.isBold(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont))
        c.redo()
        check("Redo re-applies Bold", EditorFormatting.isBold(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont))

        tv.setSelectedRange(NSRange(location: 3, length: 4))
        c.perform(.highlight(ARGB(r: 0xC5, g: 0xE1, b: 0xA5)))
        check("Highlight keeps the lock (D-4)", EditorLocking.isLocked(storage, at: 5))
        c.perform(.clearFormatting)
        check("Clear formatting keeps the lock (D-4)", EditorLocking.isLocked(storage, at: 5))

        tv.setSelectedRange(NSRange(location: 12, length: 0))
        c.perform(.alignRight)
        let align = (storage.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        check("Align right on the caret paragraph", align == .right)
        check("format bar reflects alignment", c.summary.alignment == .right)

        let lenBefore = storage.length
        c.insertTable(rows: 2, columns: 3)
        let tableParas = (0..<storage.length).filter {
            (storage.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty == false
        }.count
        check("Insert table adds 2×3 cells", tableParas == 6 && storage.length > lenBefore)
        check("caret lands in the first cell", EditorBlocks.isTableParagraph(storage, at: tv.selectedRange().location))
        tv.insertText("Part", replacementRange: tv.selectedRange())
        check("typing in the header cell is bold",
              EditorFormatting.isBold(storage.attribute(.font, at: tv.selectedRange().location - 1, effectiveRange: nil) as? NSFont))
        c.undo()
        c.undo()
        check("Undo removes the table", (0..<storage.length).allSatisfy {
            (storage.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty != false
        })

        tv.setSelectedRange(NSRange(location: storage.length, length: 0))
        let edit = EditorLinkRules.insertion(url: "https://www.imo.org/", in: storage, selection: tv.selectedRange(),
                                             typing: tv.typingAttributes, linkColor: EditorLinkRules.editorLinkColor)
        c.apply(edit, actionName: "Insert Link")
        check("link inserted at the caret", storage.string.hasSuffix("https://www.imo.org/"))
        check("link carries .link", storage.attribute(.link, at: storage.length - 2, effectiveRange: nil) != nil)

        tv.setSelectedRange(NSRange(location: 10, length: 0))
        tv.insertTab(nil)
        check("Tab outside a list inserts a tab", (storage.string as NSString).character(at: 10) == 0x09)

        tv.setSelectedRange(NSRange(location: 0, length: 0))
        c.perform(.bigger)
        check("Bigger steps the typing size by 0.75", ((tv.typingAttributes[.font] as? NSFont)?.pointSize ?? 0) == 14.75)

        // Text typed at the start of a list item (right after its marker) is item text, never marker text.
        let list = NSMutableAttributedString()
        let p = NSMutableParagraphStyle()
        p.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        var marker = base
        marker[.paragraphStyle] = p
        marker[.aaListMarker] = true
        list.append(NSAttributedString(string: "\t•\t", attributes: marker))
        var itemAttrs = base
        itemAttrs[.paragraphStyle] = p
        list.append(NSAttributedString(string: "Check oil\n", attributes: itemAttrs))
        c.showPreview(list, selection: NSRange(location: 3, length: 0))
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertText("Z", replacementRange: tv.selectedRange())
        check("typing after a list marker is item text", storage.attribute(.aaListMarker, at: 3, effectiveRange: nil) == nil
              && storage.string.hasPrefix("\t•\tZCheck"))
        return out
    }
}
