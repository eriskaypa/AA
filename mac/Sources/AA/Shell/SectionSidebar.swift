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

    var body: some View {
        let order = env.navigator.sectionOrder
        let colors = env.store.data.ui.tabColors
        let crewExpiring = CrewExpiry.expiringCount(env.store.data.crew, today: env.clock.today())
        List(selection: Binding(get: { env.navigator.selectedSection },
                                set: { if let s = $0 { env.navigator.selectSilently(s) } })) {
            ShellBrandHeader()
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            Section {
                ForEach(order, id: \.self) { s in
                    ShellSectionRow(section: s, colorHex: colors[s.rawValue],
                                    isSelected: s == env.navigator.selectedSection,
                                    badge: s == .crew && crewExpiring > 0 ? "⚠ \(crewExpiring)" : nil,
                                    position: order.firstIndex(of: s) ?? 0)
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
        }
        .listStyle(.sidebar)
        .help("Tip: drag a tab to reorder it.")
        .aaListCommands(ListCommands(role: .sectionList, selectionCount: 1,
                                     canMoveUp: order.first != env.navigator.selectedSection,
                                     canMoveDown: order.last != env.navigator.selectedSection,
                                     move: { dir in move(env.navigator.selectedSection, by: dir == .up ? -1 : 1) }))
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

/// "AA" (22 pt bold) and the tagline (SHELL-021, kept so no content is lost).
struct ShellBrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("AA")
                .font(.aaMono(AAType.brand, weight: .bold))
                .foregroundStyle(AAColor.accent)
            // The WPF tagline, verbatim, broken into lines so the narrow sidebar never truncates it.
            Text("• Equipment/Area / Tasks /\n  Procedures with containers,\n  files & relationships")
                .font(.system(size: AAType.caption))
                .foregroundStyle(AAColor.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Equipment/Area / Tasks / Procedures with containers, files & relationships")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// One section row: SF Symbol, title, ⌘-position hint, optional custom colour, active marker and Crew badge.
struct ShellSectionRow: View {
    let section: SectionID
    let colorHex: String?
    let isSelected: Bool
    let badge: String?
    let position: Int

    var body: some View {
        let custom = AAColor.tabFill(colorHex)
        HStack(spacing: 8) {
            Image(systemName: section.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(custom?.text ?? AAColor.muted)
                .frame(width: 18)
            Text(section.title)
                .fontWeight(isSelected && custom != nil ? .semibold : .regular)
                .foregroundStyle(custom?.text ?? AAColor.fg)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(AAColor.Status.dueSoon, in: Capsule())
                    .accessibilityLabel("\(badge) crew contracts expiring")
            }
        }
        .font(.system(size: AAType.body))
        .padding(.vertical, 3)
        .padding(.horizontal, custom == nil ? 0 : 6)
        .background {
            if let custom {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(custom.fill)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? AAColor.accent.opacity(0.8) : .clear, lineWidth: 1))
            }
        }
        .overlay(alignment: .leading) {
            if isSelected, custom != nil {
                Capsule().fill(AAColor.accent).frame(width: 3).padding(.vertical, 2).offset(x: -5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
