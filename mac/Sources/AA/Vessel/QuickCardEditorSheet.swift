// Spec: 10 §C (VESSEL-040 window, 041 title, 042 target display, 043 link file in place, 044 import a copy, 045 link
//       folder, 046 web link, 046a prompt, 047 title auto-fill, 048 icon picker, 049 palette, 050 custom colour,
//       051 width / height, 052 live preview, 053 tip, 054 OK / Cancel, 055 orphaned copies kept), §3.1.11, §6.3;
//       DECISIONS 10 Q6 ("Finder"); ARCHITECTURE.md §7.5 (sheet contract), §8.5 (SF Symbols for WPF emoji icons).
import AppKit
import SwiftUI
import AACore

/// The modal Quick Card editor. It edits the given card LIVE (the caller snapshots and restores on Cancel, or
/// appends a new card on OK); it never saves (VESSEL-054).
struct QuickCardEditorSheet: View {
    let card: QuickCard
    let finish: (Bool) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @FocusState private var titleFocused: Bool
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var customColor = Color.blue
    @State private var suppressColorChange = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // VESSEL-040: the Windows window title `Quick card` (a sheet has no title bar).
            HStack(spacing: AASpacing.s) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(AAColor.accent)
                Text(QuickCardLayout.noTargetTitle).font(.system(size: AAType.title, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            HStack(alignment: .top, spacing: 14) {
                form
                previewColumn.frame(width: 210)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Spacer(minLength: AASpacing.m)
            Divider()
            HStack {
                Spacer()
                Button { finish(false) } label: { Text("Cancel").frame(minWidth: 76) }
                    .keyboardShortcut(.cancelAction)
                Button { finish(true) } label: { Text("OK").frame(minWidth: 92) }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 660, height: 620)
        .background(AAColor.panel)
        .aaSheet(.decision)
        .onAppear {
            widthText = QuickCardLayout.editorSizeText(card.width)
            heightText = QuickCardLayout.editorSizeText(card.height)
            customColor = AAColor.color(MaritimeIcons.parseColor(card.color))
            DispatchQueue.main.async { titleFocused = true; suppressColorChange = false }
        }
    }

    // MARK: Left column

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Title")
            TextField("", text: Binding(get: { card.title }, set: { card.title = $0 }), prompt: Text("Card title"))
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)

            label("Target")
            HStack(spacing: AASpacing.s) {
                Text(QuickCardLayout.targetDisplay(card.target))
                    .font(.aaMono(AAType.small))
                    .foregroundStyle(NetText.isBlank(card.target) ? AAColor.muted : AAColor.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
                    .help(card.target)
                Text(QuickCardLayout.targetTypeLabel(target: card.target, kind: QuickCardLayout.kind(of: card)))
                    .font(.system(size: AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize()
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Button { Task { await linkFile() } } label: {
                        Label("Link file (in place)", systemImage: AASymbol.link).frame(maxWidth: .infinity)
                    }
                    .help("Reference a file at its original location (e.g. on a network drive) — no copy.")
                    Button { Task { await importCopy() } } label: {
                        Label("Import a copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .help("Copy the file into the app data folder.")
                }
                GridRow {
                    Button { Task { await linkFolder() } } label: {
                        Label("Link folder", systemImage: AASymbol.folder).frame(maxWidth: .infinity)
                    }
                    .help("Reference a folder (opens in Finder).")
                    Button { Task { await webLink() } } label: {
                        Label("Web link…", systemImage: AASymbol.webLink).frame(maxWidth: .infinity)
                    }
                }
            }
            .controlSize(.regular)

            label("Icon").padding(.top, 2)
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 40), spacing: 4)], spacing: 4) {
                    ForEach(Array(MaritimeIcons.all.enumerated()), id: \.offset) { _, icon in
                        QuickCardIconButton(glyph: icon.glyph, selected: Ordinal.equals(card.icon, icon.glyph)) {
                            card.icon = icon.glyph
                        }
                        .help(icon.name)
                    }
                }
                .padding(6)
            }
            .frame(height: 116)
            .background(AAColor.panelAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))

            label("Colour").padding(.top, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 10), alignment: .leading, spacing: 4) {
                ForEach(MaritimeIcons.palette, id: \.self) { hex in
                    QuickCardSwatch(hex: hex, selected: NetText.equalsIgnoreCase(card.color, hex)) { card.color = hex }
                        .help(hex)
                }
            }
            HStack(spacing: AASpacing.s) {
                ColorPicker(selection: $customColor, supportsOpacity: false) {
                    Text("Custom colour…").font(.system(size: AAType.small)).fixedSize()
                }
                .fixedSize()
                .onChange(of: customColor) { _, c in
                    guard !suppressColorChange, let s = NSColor(c).usingColorSpace(.sRGB) else { return }
                    let hex = QuickCardLayout.customColorHex(red: Double(s.redComponent), green: Double(s.greenComponent),
                                                             blue: Double(s.blueComponent))
                    if !NetText.equalsIgnoreCase(hex, card.color) { card.color = hex }
                }
                Text(card.color).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).textSelection(.enabled)
            }

            HStack(spacing: AASpacing.m) {
                label("Width")
                TextField("", text: $widthText).textFieldStyle(.roundedBorder).frame(width: 64)
                    .onChange(of: widthText) { _, t in
                        if let v = QuickCardLayout.editorWidth(from: t) { card.width = v }
                    }
                label("Height")
                TextField("", text: $heightText).textFieldStyle(.roundedBorder).frame(width: 64)
                    .onChange(of: heightText) { _, t in
                        if let v = QuickCardLayout.editorHeight(from: t) { card.height = v }
                    }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Right column (VESSEL-052, 053)

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Preview")
            let bg = MaritimeIcons.parseColor(card.color)
            let fg = AAColor.color(MaritimeIcons.readableForeground(bg))
            ZStack {
                QuickCardCheckerboard().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(bg.a < 255 ? 1 : 0)
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AAColor.color(bg))
                VStack(spacing: 0) {
                    Text(card.icon).font(.system(size: 40))
                    Text(QuickCardLayout.previewTitle(card.title))
                        .font(.system(size: 14, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .foregroundStyle(fg)
                        .padding(EdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 6))
                }
                .padding(6)
            }
            .frame(width: 190, height: 130)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .animation(.easeOut(duration: 0.15), value: card.color)
            AAHelpText(QuickCardLayout.editorTip)
                .frame(width: 190, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
    }

    // MARK: Target actions (VESSEL-043…047)

    private func linkFile() async {
        let urls = await dialogs.openPanel(OpenPanelConfig(message: "Link a file in place (no copy)"))
        guard let url = urls.first else { return }
        autoFill(QuickCardLayout.titleForFile(url))
        QuickCardLayout.setTarget(card, url.path, kind: .liveFile)
    }

    private func importCopy() async {
        let urls = await dialogs.openPanel(OpenPanelConfig(message: "Import a copy of a file"))
        guard let url = urls.first else { return }
        do {
            let stored = try AttachmentStore.importFile(env.dataStore, from: url)  // copied now (VESSEL-055)
            autoFill(QuickCardLayout.titleForFile(url))
            QuickCardLayout.setTarget(card, stored, kind: .importedCopy)
        } catch {
            await dialogs.error("Import failed", error.localizedDescription)
        }
    }

    private func linkFolder() async {
        guard let url = await dialogs.chooseFolder(message: "Link a folder (opens in Finder)", directory: nil) else { return }
        autoFill(QuickCardLayout.titleForFolder(url))
        QuickCardLayout.setTarget(card, url.path, kind: .folder)
    }

    private func webLink() async {
        let r = await dialogs.prompt(TextPromptRequest(title: "Web link", prompt: "URL:", initial: "https://"))
        guard case .ok(let text) = r, !NetText.isBlank(text) else { return }
        QuickCardLayout.setTarget(card, NetText.trim(text), kind: .webLink)        // no title auto-fill for links
    }

    /// VESSEL-047: only when the current title is blank.
    private func autoFill(_ title: String) {
        if NetText.isBlank(card.title) { card.title = title }
    }
}

/// One icon button of the editor's grid (40×36, glyph 20, the current icon highlighted — a Mac enhancement).
struct QuickCardIconButton: View {
    let glyph: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 20))
                .frame(width: 40, height: 36)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? AAColor.tint.opacity(0.22) : (hover ? AAColor.hover : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? AAColor.tint : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(MaritimeIcons.name(of: glyph) ?? glyph)
    }
}

/// One palette swatch (28×28, 1-pt border, the current colour ringed).
struct QuickCardSwatch: View {
    let hex: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AAColor.color(MaritimeIcons.parseColor(hex)))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AAColor.color(MaritimeIcons.readableForeground(MaritimeIcons.parseColor(hex))))
                    }
                }
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? AAColor.tint : Color.clear, lineWidth: 2).padding(-1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex)
    }
}

/// A light checkerboard behind semi-transparent card colours (alpha is honoured, VESSEL-013).
struct QuickCardCheckerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.22)))
                    x += 2 * s
                }
                y += s; row += 1
            }
        }
    }
}
