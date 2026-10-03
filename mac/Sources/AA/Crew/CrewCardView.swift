// Spec: 09 §C CREW-020…026 (read-only info card: header + Edit…, CONTRACT banner with a 3-pt coloured bottom rule,
//       checklist summary + Open checklist…, six bordered detail sections with a 170-pt label column and "—" for blanks,
//       review notes with severity bullets, provenance footer; values selectable, never editable), §6.4 (GroupBox-style
//       sections, SF Symbols for the section glyphs); ARCHITECTURE.md §8 (tokens, AACard, AAEmptyState).
import AppKit
import SwiftUI
import AACore

struct CrewCardPane: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Bindable var model: CrewRosterModel

    var body: some View {
        if let id = model.selectedID, let m = env.store.crewMember(id: id) {
            ScrollView {
                CrewCardView(member: m, today: model.today,
                             edit: { model.open(.details, for: m.id) },
                             openChecklist: { model.open(.checklist, for: m.id) })
                    .padding(AASpacing.l)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AAColor.bg, ignoresSafeAreaEdges: [])
            .id(m.id)
        } else if env.store.data.crew.isEmpty {
            VStack(spacing: AASpacing.m) {
                AAEmptyState(title: "No Crew Yet", symbol: "person.3",
                             message: "Import a COMPAS crew report (.xlsx) — every row becomes a read-only crew card with contract-expiry tracking.")
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await CrewActions.importCompas(env: env, dialogs: dialogs) }
                } label: { Label("Import COMPAS…", systemImage: "square.and.arrow.down.on.square") }
                .aaProminent()
                .disabled(model.importing || CrewActions.importGated(env))       // 01 DATA-174
                .help(CrewActions.importHelp(env))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AAColor.bg, ignoresSafeAreaEdges: [])
        } else {
            AAEmptyState(title: "No Crew Member Selected", symbol: "person.text.rectangle",
                         message: "Select a crew member in the roster to see their card.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AAColor.bg, ignoresSafeAreaEdges: [])
        }
    }
}

/// The card itself (also used by the snapshot registry).
struct CrewCardView: View {
    let member: CrewMember
    let today: CivilDate
    var edit: () -> Void = {}
    var openChecklist: () -> Void = {}

    var body: some View {
        let m = member
        VStack(alignment: .leading, spacing: AASpacing.m) {
            header(m)
            CrewContractBanner(member: m, today: today)
            checklistBox(m)
            ForEach(CrewRoster.sections(m)) { s in CrewCardSectionView(section: s) }
            if m.hasFlags { reviewNotes(m) }
            if let p = CrewRoster.provenance(m) {
                Text(p)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
    }

    // CREW-020 — the name beside Edit…, the subtitle below across the full card width (no wrap under the button).
    private func header(_ m: CrewMember) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: AASpacing.m) {
                Text(CrewRoster.displayName(m))
                    .font(.aaMono(AAType.title, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: AASpacing.s)
                Button(action: edit) { Label("Edit…", systemImage: "pencil") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Edit this crew member's details (including the sign-off / contract date).")
            }
            let sub = CrewRoster.subtitle(m)
            if !sub.isEmpty {
                Text(sub)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    // CREW-022
    private func checklistBox(_ m: CrewMember) -> some View {
        HStack(alignment: .top, spacing: AASpacing.m) {
            Image(systemName: "checklist")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AAColor.Status.crewAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("Checklist").font(.aaMono(AAType.body, weight: .semibold)).foregroundStyle(AAColor.accent)
                Text(CrewRoster.checklistSummary(m))
                    .font(.aaMono(AAType.caption))
                    .monospacedDigit()
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AASpacing.s)
            Button(action: openChecklist) { Label("Open Checklist…", systemImage: "list.bullet.clipboard") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Build this crew member's checklist — items with a due date show in the due-dates window and Calendar.")
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 10)
        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }

    // CREW-024
    private func reviewNotes(_ m: CrewMember) -> some View {
        AACard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Label(CrewRoster.reviewNotesTitle(m.flags.count), systemImage: "flag")
                    .font(.aaMono(AAType.body, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.fg)
                ForEach(Array(m.flags.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .imageScale(.small)
                            .font(.caption2)
                            .foregroundStyle(CrewPalette.color(f.severity))
                            .accessibilityLabel(CrewPalette.severityName(f.severity))
                        Text(CrewRoster.flagLine(f))
                            .font(.aaMono(AAType.caption))
                            .foregroundStyle(AAColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// CREW-021: PanelAlt box, radius 4, 3-pt bottom rule in the expiry colour (grey when unknown).
struct CrewContractBanner: View {
    let member: CrewMember
    let today: CivilDate

    var body: some View {
        let e = CrewExpiry.expiry(member, today: today)
        let known = CrewStoredDate.daysUntilSignOff(member, today: today) != nil
        let color = known ? CrewPalette.color(e.tone) : AAColor.Status.neutral
        HStack(alignment: .center, spacing: AASpacing.m) {
            Image(systemName: known ? (e.tone == .green ? "checkmark.seal" : "calendar.badge.exclamationmark") : "calendar.badge.minus")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("CONTRACT")
                    .font(.aaMono(AAType.caption, weight: .bold))
                    .foregroundStyle(AAColor.Status.neutral)
                Text(known ? e.text : CrewExpiry.noSignOffDate)
                    .font(.aaMono(AAType.body, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// CREW-023: one bordered section — SF Symbol + title, then a 170-pt label column.
struct CrewCardSectionView: View {
    let section: CrewCardSection

    static func symbol(_ title: String) -> String {
        switch title {
        case "Identity": return "person.text.rectangle"
        case "Employment & Sign-On / Sign-Off": return "ferry"
        case "Travel Documents": return "book.closed"
        case "Certificates & Medical": return "cross.case"
        case "Physical": return "ruler"
        default: return "person.2"
        }
    }

    var body: some View {
        AACard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label(section.title, systemImage: Self.symbol(section.title))
                    .font(.aaMono(AAType.body, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.accent)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 3) {
                    ForEach(section.fields) { f in
                        GridRow {
                            Text(f.label)
                                .font(.aaMono(AAType.body))
                                .foregroundStyle(AAColor.muted)
                                .frame(width: 170, alignment: .trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(f.display)
                                .font(.aaMono(AAType.body))
                                .foregroundStyle(NetText.isBlank(f.value) ? AAColor.muted : AAColor.fg)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
