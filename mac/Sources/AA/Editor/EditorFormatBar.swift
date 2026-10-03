// Spec: 05 §6.3 (compact in-pane format bar: grouped controls, small borderless buttons that never take the text's
//       focus, wraps when narrow, tooltips keep the Windows text with ⌘ keys; nothing dropped), CONT-020…034,
//       CONT-040…048, CONT-060/061 (every toolbar control), CONT-022 (the bar reflects the selection; the Mac also
//       shows B/I/U/S, alignment and list state), K-16; 03 §6.5.1 Format rows (same commands as the menu), SHELL-609
//       (highlight swatches never include the lock sentinel); ARCHITECTURE.md §8 (design tokens, SF Symbols).
import AppKit
import SwiftUI
import AACore

/// The format bar above the paper.
struct EditorFormatBar: View {
    let controller: EditorController

    private var s: EditorSelectionSummary { controller.summary }
    private var editable: Bool { controller.isEditable }

    var body: some View {
        EditorFlowLayout(spacing: 6, lineSpacing: 5) {
            EditorBarGroup {
                EditorFontFamilyMenu(family: s.family) { controller.applyFontFamily($0) }
                    .equatable()
                    .help("Font")
                EditorFontSizeCombo(controller: controller, size: s.size)
                    .frame(width: 58)
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

            EditorBarGroup {
                bar("text.alignleft", "Align left (⌘{)", on: s.alignment == .left || s.alignment == .natural, .alignLeft)
                bar("text.aligncenter", "Align center (⌘|)", on: s.alignment == .center, .center)
                bar("text.alignright", "Align right (⌘})", on: s.alignment == .right, .alignRight)
                bar("text.justify", "Justify", on: s.alignment == .justified, .justify)
            }

            EditorBarGroup {
                bar("list.bullet", "Bullets (⇧⌘7)", on: s.list == .bullets, .bulletedList)
                bar("list.number", "Numbered (⇧⌘9)", on: s.list == .numbered, .numberedList)
                bar("decrease.indent", "Outdent — ⌘[ (⇧Tab at the start of a list item)", .outdent)
                bar("increase.indent", "Indent — ⌘] (Tab at the start of a list item)", .indent)
            }

            EditorBarGroup {
                bar("arrow.up.to.line", "Move the current list item (or block) up — ⌃⌘↑. Sub-items move with it.", .moveItemUp)
                bar("arrow.down.to.line", "Move the current list item (or block) down — ⌃⌘↓. Sub-items move with it.", .moveItemDown)
            }

            EditorBarGroup {
                bar("link", "Insert hyperlink (⌘K)", .insertLink)
                EditorTablePickerButton(controller: controller)
                bar("list.bullet.indent", EditorSavedListInsert.buttonHelp + " (⌥⌘L)", .insertSavedList)
            }

            EditorBarGroup {
                bar("eraser", "Clear formatting", .clearFormatting)
                bar("lock", "Lock the highlighted text (password-protected; still visible everywhere, just can't be edited).",
                    .lockSelection)
                bar("lock.open", "Unlock the highlighted text (requires app password).", .unlockSelection)
            }

            EditorBarGroup {
                EditorBarButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", enabled: controller.canUndo && editable) {
                    controller.undo()
                }
                EditorBarButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: controller.canRedo && editable) {
                    controller.redo()
                }
            }

            EditorBarGroup {
                bar("magnifyingglass", "Find in this note (⌘F)", .showFind)
                EditorZoomMenu(controller: controller)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    private func bar(_ symbol: String, _ help: String, on: Bool = false, _ c: FormatCommand) -> EditorBarButton {
        EditorBarButton(symbol: symbol, help: help, isOn: on, enabled: controller.validate(c)) { controller.perform(c) }
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
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AAColor.fg)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(AAColor.border, lineWidth: 0.5))
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
                                Image(systemName: "nosign").font(.system(size: 10)).foregroundStyle(AAColor.muted)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(AAColor.border, lineWidth: 1))
                        .frame(width: 18, height: 18)
                    Text(kind == .text ? "Automatic" : "No Highlight").font(.system(size: AAType.small))
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
                Label("More Colors…", systemImage: "paintpalette").font(.system(size: AAType.small))
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
                .font(.system(size: 12))
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
                .font(.system(size: AAType.small, weight: .semibold))
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
                Label("Custom Size…", systemImage: "square.grid.3x3").font(.system(size: AAType.small))
            }
            .buttonStyle(.plain)
            Text("The first row is a bold header row.")
                .font(.system(size: AAType.caption))
                .foregroundStyle(AAColor.muted)
        }
        .padding(12)
    }
}

// MARK: - Zoom (Mac addition; pinch works too)

struct EditorZoomMenu: View {
    let controller: EditorController

    var body: some View {
        Menu {
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
        } label: {
            Text("\(Int((controller.zoom * 100).rounded()))%")
                .font(.system(size: AAType.caption, weight: .medium).monospacedDigit())
                .foregroundStyle(AAColor.fg)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
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
    let apply: (String) -> Void

    nonisolated static func == (a: EditorFontFamilyMenu, b: EditorFontFamilyMenu) -> Bool { a.family == b.family }

    var body: some View {
        Menu {
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
                .font(.system(size: AAType.caption))
                .lineLimit(1)
                .truncationMode(.tail)
        }
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

        @MainActor func commit(_ box: NSComboBox) {
            guard !applying, let v = EditorFontCatalog.parseSize(box.stringValue) else { return }
            applying = true
            controller.applyFontSize(v)
            applying = false
        }

        @MainActor @objc func entered(_ sender: NSComboBox) { commit(sender) }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                      let v = box.itemObjectValue(at: box.indexOfSelectedItem) as? String,
                      let size = EditorFontCatalog.parseSize(v) else { return }
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
