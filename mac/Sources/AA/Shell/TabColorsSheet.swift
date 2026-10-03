// Spec: 03 SHELL-029 (Customize tab colors: intro, rows in display order, swatch / default, Pick… (alpha dropped,
//       "#RRGGBB" upper-case), Default, Reset all, Cancel, Apply → Ui.TabColors + MarkDirty; working copy keeps entries for
//       unknown tabs), §6.7 (Mac sheet, NSColorPanel showsAlpha = false, sRGB bytes), SHELL-639.
import AppKit
import SwiftUI
import AACore

struct TabColorsSheet: View {
    @Environment(AppEnvironment.self) private var env
    let dismiss: () -> Void
    /// A copy of the current map (entries for tabs that no longer exist are preserved, 03 §3.12).
    @State private var working: OrderedMap<String>?
    @State private var picker = ShellColorPanelBridge()

    var body: some View {
        let map = working ?? env.store.data.ui.tabColors
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text("Customize tab colors").font(.system(size: 14, weight: .bold))
            Text("Pick a background colour for each main tab. The active tab keeps its colour with an accent underline. 'Default' restores the theme colour.")
                .font(.system(size: AAType.small))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(env.navigator.sectionOrder, id: \.self) { s in
                        row(s, map: map)
                        if s != env.navigator.sectionOrder.last { Divider().opacity(0.5) }
                    }
                }
                .padding(.horizontal, AASpacing.s)
            }
            .frame(minHeight: 360)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border))

            HStack {
                Button("Reset All") { working = OrderedMap() }
                Spacer()
                Button("Cancel", role: .cancel) { picker.close(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .frame(minWidth: 90)
                Button("Apply") { apply(map) }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .frame(minWidth: 90)
            }
        }
        .padding(AASpacing.l)
        .frame(width: 480, height: 560)
        .aaSheet(.decision)
        .onDisappear { picker.close() }
    }

    private func row(_ s: SectionID, map: OrderedMap<String>) -> some View {
        let hex = map[s.rawValue]
        let fill = AAColor.tabFill(hex)
        return HStack(spacing: AASpacing.s) {
            Label(s.title, systemImage: s.symbol)                 // CrewTab is always "Crew" here
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 190, alignment: .leading)
            AAColorSwatch(color: fill?.fill)
                .overlay {
                    if let fill {
                        Text("Aa").font(.system(size: 11, weight: .semibold)).foregroundStyle(fill.text)
                    }
                }
            Spacer()
            Button("Pick…") {
                picker.open(initial: ShellTabColor.parse(hex)) { newHex in
                    var m = working ?? env.store.data.ui.tabColors
                    m[s.rawValue] = newHex
                    working = m
                }
            }
            Button("Default") {
                var m = working ?? env.store.data.ui.tabColors
                m[s.rawValue] = nil
                working = m
            }
            .disabled(hex == nil)
        }
        .padding(.vertical, 6)
    }

    private func apply(_ map: OrderedMap<String>) {
        picker.close()
        if map != env.store.data.ui.tabColors {
            env.store.data.ui.tabColors = map
            env.store.markDirty()
        }
        dismiss()
    }
}

/// Bridges `NSColorPanel` (alpha hidden, sRGB conversion) to a SwiftUI callback.
@MainActor final class ShellColorPanelBridge: NSObject {
    private var onPick: ((String) -> Void)?

    func open(initial: ARGB?, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        if let c = initial { panel.color = AAColor.ns(ARGB(r: c.r, g: c.g, b: c.b)) }
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    func close() {
        guard onPick != nil else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        onPick = nil
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        onPick?(ShellTabColor.hex(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                                  blue: Double(srgb.blueComponent)))
    }
}
