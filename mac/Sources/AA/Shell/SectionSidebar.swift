// Spec: 03 SHELL-021 (brand + tagline), SHELL-025 (13 sections), SHELL-028 (drag reorder → TabOrder + MarkDirty),
//       SHELL-029 (custom colours, contrast text, active marker), SHELL-030 (Crew badge), SHELL-031 (tooltip on the
//       sidebar only), SHELL-522 (↑/↓ in the sidebar), §6.2 (Mac rendition; Move Up / Move Down context menu);
//       ARCHITECTURE.md §7.2.
import AppKit
import SwiftUI
import AACore

/// The WPF tab strip as a Mac sidebar.
struct SectionSidebar: View {
    @Environment(AppEnvironment.self) private var env
    /// §6.4 / DEVIATIONS W-CREW "roster": the Crew badge rolls over at local midnight (NSCalendarDayChanged), like the
    /// roster capsule.
    @State private var dayTick = 0

    var body: some View {
        let order = env.navigator.sectionOrder
        let colors = env.store.data.ui.tabColors
        let _ = dayTick                                         // re-evaluated at the day change
        let crewExpiring = CrewExpiry.expiringCount(env.store.data.crew, today: env.clock.today())
        VStack(alignment: .leading, spacing: 0) {
        // The brand header is fixed above the list (it never scrolls away with the sections).
        ShellBrandHeader()
        List(selection: Binding(get: { env.navigator.selectedSection },
                                set: { if let s = $0 { env.navigator.selectSilently(s) } })) {
            ForEach(order, id: \.self) { s in
                ShellSectionRow(section: s, colorHex: colors[s.rawValue],
                                isSelected: s == env.navigator.selectedSection,
                                position: order.firstIndex(of: s) ?? 0)
                    .badge(s == .crew && crewExpiring > 0 ? Text("⚠ \(crewExpiring)").monospacedDigit() : nil)
                    .accessibilityValue(s == .crew && crewExpiring > 0 ? "\(crewExpiring) crew contracts expiring" : "")
                    .tag(s)
                    .contextMenu {
                        Button("Move Up") { move(s, by: -1) }.disabled(order.first == s)
                        Button("Move Down") { move(s, by: 1) }.disabled(order.last == s)
                        Divider()
                        Button("Customize Tab Colors…") { env.router.perform(.tabColors) }
                    }
            }
            .onMove { from, to in
                withAnimation(.snappy) { env.navigator.moveSections(from: from, to: to) }
            }
        }
        .listStyle(.sidebar)
        .help("Tip: drag a tab to reorder it.")
        .aaListCommands(ListCommands(role: .sectionList, selectionCount: 1,
                                     canMoveUp: order.first != env.navigator.selectedSection,
                                     canMoveDown: order.last != env.navigator.selectedSection,
                                     move: { dir in move(env.navigator.selectedSection, by: dir == .up ? -1 : 1) }))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            dayTick &+= 1
        }
    }

    private func move(_ s: SectionID, by delta: Int) {
        var order = env.navigator.sectionOrder
        guard let i = order.firstIndex(of: s) else { return }
        let j = i + delta
        guard order.indices.contains(j) else { return }
        order.swapAt(i, j)
        withAnimation(.snappy) { env.navigator.applyOrder(order) }
    }
}

/// "AA" (22 pt bold mono) and the tagline (SHELL-021, kept verbatim so no content is lost) — a fixed header above the
/// section list; the tagline wraps naturally in the sidebar width.
struct ShellBrandHeader: View {
    static let tagline = "• Equipment/Area / Tasks / Procedures with containers, files & relationships"

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.xs) {
            Text("AA")
                .font(.aaMono(AAType.brand, weight: .bold))
                .foregroundStyle(AAColor.accent)
            Text(Self.tagline)
                .font(.caption)
                .foregroundStyle(AAColor.muted)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .accessibilityLabel("Equipment/Area / Tasks / Procedures with containers, files & relationships")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AASpacing.l)
        .padding(.top, AASpacing.xs)
        .padding(.bottom, AASpacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One section row: SF Symbol (on a 20×20 colour tile when the section has a custom colour, glyph in the SHELL-029
/// contrast colour) and the title. Native sidebar selection; a coloured section's active row adds a semibold title and
/// a 2-pt accent underline under the label (03 §6.2 / SHELL-029 active marker, DEVIATIONS F3 "sidebar colour").
struct ShellSectionRow: View {
    let section: SectionID
    let colorHex: String?
    let isSelected: Bool
    let position: Int

    var body: some View {
        let custom = AAColor.tabFill(colorHex)
        Label {
            Text(section.title)
                .fontWeight(isSelected && custom != nil ? .semibold : .regular)
                .foregroundStyle(AAColor.fg)
                .lineLimit(1)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    if isSelected, custom != nil {
                        Capsule().fill(AAColor.accent).frame(height: 2)
                            .accessibilityHidden(true)
                    }
                }
        } icon: {
            if let custom {
                Image(systemName: section.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(custom.text)
                    .imageScale(.small)
                    .frame(width: 20, height: 20)
                    .background(custom.fill, in: RoundedRectangle(cornerRadius: AARadius.sidebarTile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AARadius.sidebarTile, style: .continuous)
                        .strokeBorder(AAColor.border, lineWidth: 0.5))
            } else {
                Image(systemName: section.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.muted)
                    .frame(width: 20, height: 20)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
