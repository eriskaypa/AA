// Spec: 05 §6.3 (compact in-pane format bar: grouped controls, small borderless buttons that never take the text's
//       focus, wraps when narrow, tooltips keep the Windows text with ⌘ keys; nothing dropped), CONT-020…034,
//       CONT-040…048, CONT-060/061 (every toolbar control), CONT-022 (the bar reflects the selection; the Mac also
//       shows B/I/U/S, alignment and list state), K-16; 03 §6.5.1 Format rows (same commands as the menu), SHELL-609
//       (highlight swatches never include the lock sentinel); ARCHITECTURE.md §8 (design tokens, SF Symbols).
import AppKit
import SwiftUI
import AACore

/// The format bar above the paper. It never wraps a lone group onto a second row: as the pane narrows, alignment and
/// lists fold into pop-up menus, then the less frequent groups move into a trailing overflow menu (05 §6.3 "wrapping
/// into an overflow Menu when narrow"); only a pane too narrow even for that wraps. Every command keeps its tooltip
/// and stays reachable under its Format-menu name (V-DESIGN rule 4).
struct EditorFormatBar: View {
    let controller: EditorController

    private var s: EditorSelectionSummary { controller.summary }
    private var editable: Bool { controller.isEditable }

    /// How much of the bar is folded away (each step keeps everything the previous one showed reachable).
    enum Density: Int, Comparable {
        /// Every group inline (Windows toolbar order).
        case full
        /// Alignment and lists become pop-up menus.
        case compact
        /// + insert saved list / move, lock / unlock, find / zoom go into the trailing overflow menu.
        case overflow
        /// + undo / redo and link / table / clear go into the overflow menu too.
        case minimal

        static func < (a: Density, b: Density) -> Bool { a.rawValue < b.rawValue }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.compact)
            row(.overflow)
            row(.minimal)
            EditorFlowLayout(spacing: 6, lineSpacing: 5) { groups(.minimal) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    private func row(_ d: Density) -> some View {
        HStack(spacing: 6) { groups(d) }.fixedSize()
    }

    @ViewBuilder private func groups(_ d: Density) -> some View {
        EditorBarGroup {
            EditorFontFamilyMenu(family: s.family, showFonts: { controller.perform(.showFonts) }) {
                controller.applyFontFamily($0)
            }
                .equatable()
                .help("Font")
            EditorFontSizeCombo(controller: controller, size: s.size)
                .frame(width: 66)
                .help("Font size (⌘+ / ⌘− step it)")
        }
        .disabled(!editable)

        EditorBarGroup {
            bar("bold", "Bold (⌘B)", on: s.bold, .bold)
            bar("italic", "Italic (⌘I)", on: s.italic, .italic)
            bar("underline", "Underline (⌘U)", on: s.underline, .underline)
            bar("strikethrough", "Strikethrough (⇧⌘X)", on: s.strikethrough, .strikethrough)
        }

        EditorBarGroup {
            EditorColorButton(controller: controller, kind: .text, current: s.foreground)
            EditorColorButton(controller: controller, kind: .highlight, current: s.highlight)
        }
        .disabled(!editable)

        if d == .full {
            EditorBarGroup {
                ForEach(Self.alignments, id: \.title) { a in bar(a.symbol, a.help, on: a.isOn(s.alignment), a.command) }
            }
        } else {
            EditorBarGroup { alignmentMenu }
        }

        // Windows toolbar order (ContainerEditor.xaml:21-55): lists and indent, saved list + move, undo/redo,
        // link / table / clear, lock / unlock.
        if d == .full {
            EditorBarGroup {
                ForEach(Self.listCommands, id: \.title) { c in bar(c.symbol, c.help, on: c.isOn(s.list), c.command) }
            }
        } else {
            EditorBarGroup { listMenu }
        }

        if d < .overflow {
            EditorBarGroup {
                ForEach(Self.blockCommands, id: \.title) { c in bar(c.symbol, c.help, c.command) }
            }
        }

        if d < .minimal {
            EditorBarGroup {
                EditorBarButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", enabled: controller.canUndo && editable) {
                    controller.undo()
                }
                EditorBarButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: controller.canRedo && editable) {
                    controller.redo()
                }
            }

            EditorBarGroup {
                bar("link", "Insert hyperlink (⌘K)", .insertLink)
                EditorTablePickerButton(controller: controller)
                bar("eraser", "Clear formatting", .clearFormatting)
            }
        }

        if d < .overflow {
            EditorBarGroup {
                ForEach(Self.lockCommands, id: \.title) { c in bar(c.symbol, c.help, c.command) }
            }

            EditorBarGroup {
                bar("magnifyingglass", "Find in this note (⌘F)", .showFind)
                EditorZoomMenu(controller: controller)
            }
        } else {
            EditorBarGroup { overflowMenu(d) }
        }
    }

    private func bar(_ symbol: String, _ help: String, on: Bool = false, _ c: FormatCommand) -> EditorBarButton {
        EditorBarButton(symbol: symbol, help: help, isOn: on, enabled: controller.validate(c)) { controller.perform(c) }
    }

    // MARK: Command tables (one source for the buttons and the folded menus)

    struct BarCommand {
        let title: String                 // the Format-menu name (03 §6.5.1 / ShortcutRegistry)
        let symbol: String
        let help: String                  // the format-bar tooltip (05 §6.3)
        let command: FormatCommand
        var alignment: [NSTextAlignment] = []
        var list: EditorSelectionSummary.ListKind?

        func isOn(_ a: NSTextAlignment?) -> Bool { a.map(alignment.contains) ?? false }
        func isOn(_ l: EditorSelectionSummary.ListKind) -> Bool { list != nil && l == list }
    }

    static let alignments: [BarCommand] = [
        BarCommand(title: "Align Left", symbol: "text.alignleft", help: "Align left (⌘{)", command: .alignLeft,
                   alignment: [.left, .natural]),
        BarCommand(title: "Center", symbol: "text.aligncenter", help: "Align center (⌘|)", command: .center,
                   alignment: [.center]),
        BarCommand(title: "Align Right", symbol: "text.alignright", help: "Align right (⌘})", command: .alignRight,
                   alignment: [.right]),
        BarCommand(title: "Justify", symbol: "text.justify", help: "Justify", command: .justify, alignment: [.justified]),
    ]

    static let listCommands: [BarCommand] = [
        BarCommand(title: "Bulleted List", symbol: "list.bullet", help: "Bullets (⇧⌘7)", command: .bulletedList,
                   list: .bullets),
        BarCommand(title: "Numbered List", symbol: "list.number", help: "Numbered (⇧⌘9)", command: .numberedList,
                   list: .numbered),
        BarCommand(title: "Indent", symbol: "increase.indent", help: "Indent — ⌘] (Tab at the start of a list item)",
                   command: .indent),
        BarCommand(title: "Outdent", symbol: "decrease.indent", help: "Outdent — ⌘[ (⇧Tab at the start of a list item)",
                   command: .outdent),
    ]

    static let blockCommands: [BarCommand] = [
        BarCommand(title: "Saved List…", symbol: "text.badge.plus", help: EditorSavedListInsert.buttonHelp + " (⌥⌘L)",
                   command: .insertSavedList),
        BarCommand(title: "Move Up", symbol: "arrow.up.to.line",
                   help: "Move the current list item (or block) up — ⌃⌘↑. Sub-items move with it.", command: .moveItemUp),
        BarCommand(title: "Move Down", symbol: "arrow.down.to.line",
                   help: "Move the current list item (or block) down — ⌃⌘↓. Sub-items move with it.",
                   command: .moveItemDown),
    ]

    static let lockCommands: [BarCommand] = [
        BarCommand(title: "Lock Highlighted Text…", symbol: "lock",
                   help: "Lock the highlighted text (password-protected; still visible everywhere, just can't be edited).",
                   command: .lockSelection),
        BarCommand(title: "Unlock Highlighted Text…", symbol: "lock.open",
                   help: "Unlock the highlighted text (requires app password).", command: .unlockSelection),
    ]

    // MARK: Folded menus

    private func menuItem(_ c: BarCommand, on: Bool = false) -> some View {
        Button { controller.perform(c.command) } label: {
            Label(c.title, systemImage: on ? "checkmark" : c.symbol)
        }
        .disabled(!controller.validate(c.command))
        .help(c.help)
    }

    private var alignmentMenu: some View {
        let current = Self.alignments.first { $0.isOn(s.alignment) } ?? Self.alignments[0]
        return EditorBarMenu(symbol: current.symbol, help: "Alignment — " + current.help, label: "Alignment") {
            ForEach(Self.alignments, id: \.title) { a in menuItem(a, on: a.isOn(s.alignment)) }
        }
    }

    private var listMenu: some View {
        let current = Self.listCommands.first { $0.isOn(s.list) }
        return EditorBarMenu(symbol: current?.symbol ?? "list.bullet", isOn: current != nil,
                             help: "Lists — bullets, numbering, indent and outdent", label: "Lists") {
            ForEach(Self.listCommands.prefix(2), id: \.title) { c in menuItem(c, on: c.isOn(s.list)) }
            Divider()
            ForEach(Self.listCommands.suffix(2), id: \.title) { c in menuItem(c) }
        }
    }

    private func overflowMenu(_ d: Density) -> some View {
        EditorBarMenu(symbol: "ellipsis.circle", help: "More formatting commands", label: "More") {
            if d >= .minimal {
                Button { controller.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!(controller.canUndo && editable))
                Button { controller.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!(controller.canRedo && editable))
                Divider()
                menuItem(BarCommand(title: "Link…", symbol: "link", help: "Insert hyperlink (⌘K)", command: .insertLink))
                menuItem(BarCommand(title: "Table…", symbol: "tablecells",
                                    help: "Insert a table. You can also paste tables directly from Excel, Word or the web.",
                                    command: .insertTable))
                menuItem(BarCommand(title: "Clear Formatting", symbol: "eraser", help: "Clear formatting",
                                    command: .clearFormatting))
                Divider()
            }
            ForEach(Self.blockCommands, id: \.title) { c in menuItem(c) }
            Divider()
            ForEach(Self.lockCommands, id: \.title) { c in menuItem(c) }
            Divider()
            menuItem(BarCommand(title: "Find in Note…", symbol: "magnifyingglass", help: "Find in this note (⌘F)",
                                command: .showFind))
            Menu {
                EditorZoomMenu.items(controller)
            } label: {
                Label("Zoom (\(Int((controller.zoom * 100).rounded()))%)", systemImage: "plus.magnifyingglass")
            }
        }
    }
}

/// A folded group: a borderless pop-up with an SF Symbol label (same size and states as `EditorBarButton`).
struct EditorBarMenu<Content: View>: View {
    let symbol: String
    var isOn = false
    let help: String
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu { content() } label: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? AAColor.tint : AAColor.fg)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(AAColor.fg)
        .fixedSize()
        .frame(height: 22)
        .padding(.horizontal, 4)
        .focusable(false)
        .help(help)
        .accessibilityLabel(label)
    }
}

// MARK: - Building blocks

/// A rounded group of related controls (Pages-style segment).
struct EditorBarGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 1) { content() }
            .padding(2)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }
}

/// A small borderless icon button with hover and "on" states; never takes keyboard focus from the text.
struct EditorBarButton: View {
    let symbol: String
    let help: String
    var isOn = false
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: AAType.small, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? AAColor.tint : AAColor.fg)
                .frame(width: 25, height: 22)
                .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .aaDisabledOpacity(!enabled)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: Color {
        if isOn { return AAColor.tint.opacity(hovering ? 0.26 : 0.18) }
        return hovering && enabled ? AAColor.hover : .clear
    }
}

/// Wraps its children onto further lines when the pane is narrow (the WPF toolbar is a WrapPanel).
struct EditorFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Colours (CONT-025 / CONT-026, SHELL-608 / SHELL-609)

enum EditorColorKind { case text, highlight }

struct EditorColorButton: View {
    let controller: EditorController
    let kind: EditorColorKind
    let current: NSColor?
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            VStack(spacing: 1) {
                Image(systemName: kind == .text ? "character" : "highlighter")
                    .font(.system(size: AAType.caption, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.fg)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(AAColor.muted.opacity(0.55), lineWidth: 0.5))
                    .frame(width: 14, height: 3)
            }
            .frame(width: 30, height: 22)
            .background(hovering || open ? AAColor.hover : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(kind == .text ? "Text color" : "Highlight")
        .accessibilityLabel(kind == .text ? "Text color" : "Highlight")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            EditorColorPalette(kind: kind) { choice in
                open = false
                switch choice {
                case .color(let c): kind == .text ? controller.applyTextColor(c) : controller.applyHighlight(c)
                case .automatic: kind == .text ? controller.applyTextColor(nil) : controller.applyHighlight(nil)
                case .other: controller.openColorPanel(highlight: kind == .highlight)
                }
            }
        }
    }

    private var barColor: Color {
        switch kind {
        case .text: return Color(nsColor: current ?? EditorFormatting.editorInk)
        case .highlight: return current.map { Color(nsColor: $0) } ?? Color.clear
        }
    }
}

enum EditorColorChoice { case color(NSColor), automatic, other }

/// The swatch grid inside the colour popovers.
struct EditorColorPalette: View {
    let kind: EditorColorKind
    let choose: (EditorColorChoice) -> Void

    /// Text colours: the ink plus a theme row and Office's standard row.
    static let textRows: [[UInt32]] = [
        [0x000000, 0x404040, 0x7F7F7F, 0xA5A5A5, 0x44546A, 0x4472C4, 0x5B9BD5, 0x70AD47, 0xED7D31, 0x7030A0],
        [0xC00000, 0xFF0000, 0xFFC000, 0xFFD966, 0x92D050, 0x00B050, 0x00B0F0, 0x0070C0, 0x002060, 0x9C27B0],
    ]
    /// Highlights: router swatches first (SHELL-609), then a few more; never #FFE699 (the lock sentinel).
    static let highlightRow: [UInt32] = [0xFFF59D, 0xC5E1A5, 0xB3E5FC, 0xF8BBD0, 0xFFCC80, 0xD1C4E9, 0xE0E0E0, 0xFFAB91]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { choose(.automatic) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(kind == .text ? Color(nsColor: EditorFormatting.editorInk) : Color.clear)
                        .overlay {
                            if kind == .highlight {
                                Image(systemName: "nosign").font(.caption2).foregroundStyle(AAColor.muted)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(AAColor.border, lineWidth: 1))
                        .frame(width: 18, height: 18)
                    Text(kind == .text ? "Automatic" : "No Highlight").font(.callout)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if kind == .text {
                ForEach(Array(Self.textRows.enumerated()), id: \.offset) { _, row in swatchRow(row) }
            } else {
                swatchRow(Self.highlightRow)
            }

            Divider()
            Button { choose(.other) } label: {
                Label("More Colors…", systemImage: "paintpalette").font(.callout)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: kind == .text ? 252 : 210)
    }

    private func swatchRow(_ row: [UInt32]) -> some View {
        HStack(spacing: 4) {
            ForEach(row, id: \.self) { rgb in
                EditorSwatch(color: Self.nsColor(rgb)) { choose(.color(Self.nsColor(rgb))) }
            }
        }
    }

    static func nsColor(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

struct EditorSwatch: View {
    let color: NSColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(hovering ? AAColor.tint : AAColor.border, lineWidth: hovering ? 2 : 1))
                .frame(width: 20, height: 20)
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
        .help(WpfColor.hexAARRGGBB(ARGB(r: UInt8((color.redComponent * 255).rounded()),
                                        g: UInt8((color.greenComponent * 255).rounded()),
                                        b: UInt8((color.blueComponent * 255).rounded()))))
    }
}

// MARK: - Table picker (CONT-032; the grid is a Mac addition, "Custom Size…" is the B5 prompt)

struct EditorTablePickerButton: View {
    let controller: EditorController
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "tablecells")
                .font(.system(size: AAType.small, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AAColor.fg)
                .frame(width: 25, height: 22)
                .background(hovering || open ? AAColor.hover : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!controller.validate(.insertTable))
        .aaDisabledOpacity(!controller.validate(.insertTable))
        .onHover { hovering = $0 }
        .help("Insert a table. You can also paste tables directly from Excel, Word or the web.")
        .accessibilityLabel("Insert table")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            EditorTableGrid { rows, cols in
                open = false
                controller.insertTable(rows: rows, columns: cols)
            } custom: {
                open = false
                controller.perform(.insertTable)
            }
        }
    }
}

struct EditorTableGrid: View {
    let pick: (Int, Int) -> Void
    let custom: () -> Void
    static let rows = 8, cols = 10
    @State private var hover: (r: Int, c: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hover.map { "\($0.r + 1) × \($0.c + 1) table" } ?? "Insert table")
                .font(.aaMono(AAType.small, weight: .semibold).monospacedDigit())
                .foregroundStyle(AAColor.fg)
            VStack(spacing: 3) {
                ForEach(0..<Self.rows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<Self.cols, id: \.self) { c in
                            let lit = hover.map { r <= $0.r && c <= $0.c } ?? false
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(lit ? AAColor.tint.opacity(0.35) : AAColor.panel)
                                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(lit ? AAColor.tint : AAColor.border, lineWidth: 1))
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                                .onHover { inside in if inside { hover = (r, c) } }
                                .onTapGesture { pick(r + 1, c + 1) }
                        }
                    }
                }
            }
            .onHover { inside in if !inside { hover = nil } }
            Divider()
            Button { custom() } label: {
                Label("Custom Size…", systemImage: "square.grid.3x3").font(.callout)
            }
            .buttonStyle(.plain)
            Text("The first row is a bold header row.")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
        }
        .padding(12)
    }
}

// MARK: - Zoom (Mac addition; pinch works too)

struct EditorZoomMenu: View {
    let controller: EditorController

    /// The zoom levels plus Actual Size (shared with the format bar's overflow menu).
    @ViewBuilder static func items(_ controller: EditorController) -> some View {
        ForEach(EditorController.zoomLevels, id: \.self) { z in
            Button { controller.setZoom(z) } label: {
                if abs(controller.zoom - z) < 0.001 {
                    Label("\(Int((z * 100).rounded()))%", systemImage: "checkmark")
                } else {
                    Text("\(Int((z * 100).rounded()))%")
                }
            }
        }
        Divider()
        Button("Actual Size") { controller.setZoom(1) }
    }

    var body: some View {
        Menu {
            Self.items(controller)
        } label: {
            Text("\(Int((controller.zoom * 100).rounded()))%")
                .font(.aaMono(AAType.caption, weight: .medium).monospacedDigit())
                .foregroundStyle(AAColor.fg)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(AAColor.fg)
        .fixedSize()
        .frame(height: 22)
        .padding(.horizontal, 4)
        .help("Zoom this note (pinch to zoom)")
    }
}

// MARK: - Font family and size (CONT-020…022, K-16)

/// The family menu: shows the stored token (XD.5), lists every installed family once per process (CONT-020).
struct EditorFontFamilyMenu: View, Equatable {
    let family: String?
    let showFonts: () -> Void
    let apply: (String) -> Void

    nonisolated static func == (a: EditorFontFamilyMenu, b: EditorFontFamilyMenu) -> Bool { a.family == b.family }

    var body: some View {
        Menu {
            Button("Show Fonts… (⌘T)") { showFonts() }
            Divider()
            if let family, !EditorFontCatalog.isInstalled(family) {
                Section("Stored in this note (shown with a substitute)") {
                    Button(family) { apply(family) }
                }
            }
            ForEach(EditorFontCatalog.families, id: \.self) { f in
                Button(f) { apply(f) }
            }
        } label: {
            Text(family ?? "—")
                .font(.subheadline)
                .foregroundStyle(AAColor.fg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .tint(AAColor.fg)
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .frame(width: 128, height: 22, alignment: .leading)
        .padding(.leading, 6)
        .accessibilityLabel("Font")
    }
}

struct EditorFontSizeCombo: NSViewRepresentable {
    let controller: EditorController
    let size: CGFloat?

    final class Coordinator: NSObject, NSComboBoxDelegate {
        let controller: EditorController
        var applying = false
        init(controller: EditorController) { self.controller = controller }

        /// K-16: a typed size applies on commit. Leaving the box without changing what it shows applies nothing
        /// (K-7: never stamp an identical size onto the selection).
        @MainActor func commit(_ box: NSComboBox) {
            guard !applying, box.stringValue != EditorFontCatalog.displaySize(controller.summary.size),
                  let v = EditorFontCatalog.parseSize(box.stringValue) else { return }
            applying = true
            controller.applyFontSize(v)
            applying = false
        }

        @MainActor @objc func entered(_ sender: NSComboBox) { commit(sender) }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                      let v = box.itemObjectValue(at: box.indexOfSelectedItem) as? String,
                      let size = EditorFontCatalog.parseSize(v), size != controller.summary.size else { return }
                applying = true
                controller.applyFontSize(size)
                applying = false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            MainActor.assumeIsolated {
                if let box = obj.object as? NSComboBox { commit(box) }   // K-16: applies on commit
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSComboBox {
        let c = NSComboBox(frame: .zero)
        c.controlSize = .small
        c.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        c.addItems(withObjectValues: EditorFormatting.standardSizes.map { EditorFontCatalog.displaySize($0) })
        c.numberOfVisibleItems = 15
        c.completes = false
        c.delegate = context.coordinator
        c.target = context.coordinator
        c.action = #selector(Coordinator.entered(_:))
        c.setAccessibilityLabel("Font size")
        return c
    }

    func updateNSView(_ c: NSComboBox, context: Context) {
        let text = EditorFontCatalog.displaySize(size)
        if c.currentEditor() == nil, c.stringValue != text { c.stringValue = text }
    }
}
