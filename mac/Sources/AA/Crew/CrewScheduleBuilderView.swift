// Spec: 06 §I BUILD-110…125 (crew schedule builder: vessel link bar, add row, timeline grouped by day, ✎ / ✕ rows,
//       count line, Save as / Apply saved / Export / Import), BUILD-A15/A16, §6.5 (Mac layout: Picker, SF Symbols,
//       visible placeholders "HH:mm" and "What… (or pick an item)", OptionalDatePicker defaulting to today, List with a
//       Section per day, hover-revealed pencil / xmark); 09 §H CREW-080…086; 02 REPO-155; 06 Addendum caller rows 7–8
//       (prompts) and VIEW-212 rows 16–17 (single-select pickers); ARCHITECTURE.md §2.4 (resolve the crew by id).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

struct CrewScheduleBuilderView: View {
    let crewID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var addDate: NetDateTime?
    @State private var time = ""
    @State private var kindRaw = ScheduleKind.note.rawValue
    @State private var title = ""
    @State private var pendingRef: UUID?
    @State private var bound = false

    private var kind: ScheduleKind { ScheduleKind(rawValue: kindRaw) }

    var body: some View {
        if let crew = env.store.crewMember(id: crewID) {
            content(crew)
                .onAppear { if !bound { bind() } }
        } else {
            AAEmptyState(title: "Crew Member Not Found", symbol: "person.crop.circle.badge.questionmark",
                         message: "This crew member is no longer in the roster.")
        }
    }

    /// `Bind`: the add-row date back to today (BUILD-112/122).
    private func bind() {
        bound = true
        addDate = .calendarDate(env.clock.today())
    }

    private func content(_ crew: CrewMember) -> some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            topBar(crew)
            addRow(crew)
            timeline(crew)
            Text(CrewScheduleTimeline.countLine(crew.schedule))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
        }
    }

    // MARK: BUILD-111 top bar

    private func topBar(_ crew: CrewMember) -> some View {
        let choices = CrewScheduleOps.vesselChoices(env.store.data)
        let selection = Binding<UUID?>(
            get: { CrewScheduleOps.selectedVessel(crew, data: env.store.data) },
            set: { v in
                guard v != CrewScheduleOps.selectedVessel(crew, data: env.store.data) else { return }
                crew.scheduleVesselId = v
                CrewPersist.save(env)
            })
        return CrewFlowLayout(spacing: 6, lineSpacing: 6) {
            HStack(spacing: 6) {
                Text(CrewScheduleText.linkedVessel).font(.aaMono(AAType.small))
                Picker(CrewScheduleText.linkedVessel, selection: selection) {
                    ForEach(choices, id: \.id) { c in Text(c.name).tag(c.id) }
                }
                .labelsHidden()
                .frame(width: 180)
                .help(CrewScheduleText.linkedVesselHelp)
            }
            Button { Task { await saveAs(crew) } } label: {
                Label(CrewScheduleText.saveAs, systemImage: "square.and.arrow.down")
            }
            .help(CrewScheduleText.saveAsHelp)
            Button { Task { await applySaved(crew) } } label: {
                Label(CrewScheduleText.applySaved, systemImage: "list.clipboard")
            }
            .help(CrewScheduleText.applySavedHelp)
            Button { Task { await export(crew) } } label: {
                Label(CrewScheduleText.export, systemImage: "square.and.arrow.up")
            }
            .help(CrewScheduleText.exportHelp)
            Button { Task { await importFile(crew) } } label: {
                Label(CrewScheduleText.importTitle, systemImage: "square.and.arrow.down.on.square")
            }
            .help(CrewScheduleText.importHelp)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
        .padding(AASpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }

    // MARK: BUILD-112…115 add row

    private func addRow(_ crew: CrewMember) -> some View {
        CrewFlowLayout(spacing: 6, lineSpacing: 6) {
            Text(CrewScheduleText.add).font(.aaMono(AAType.small, weight: .bold))
            OptionalDatePicker(value: $addDate)
            TextField(CrewScheduleText.timePlaceholder, text: $time)
                .textFieldStyle(.roundedBorder)
                .font(.aaMono(AAType.small))
                .frame(width: 60)
                .help(CrewScheduleText.timeHelp)
            Picker("Kind", selection: Binding(get: { kindRaw }, set: { kindRaw = $0; pendingRef = nil })) {
                ForEach(CrewScheduleText.kinds, id: \.rawValue) { k in Text(CrewScheduleText.kindName(k)).tag(k.rawValue) }
            }
            .labelsHidden()
            .frame(width: 110)
            TextField(CrewScheduleText.titlePlaceholder, text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { Task { await add(crew) } }
            Button(CrewScheduleText.pickItem) { Task { await pick() } }
                .disabled(kind == .note)
                .help(CrewScheduleText.pickItemHelp)
            Button { Task { await add(crew) } } label: { Label("Add", systemImage: "plus") }
                .aaProminent()
                .help(CrewScheduleText.addButton)
        }
        .controlSize(.small)
    }

    private func pick() async {
        let items = CrewScheduleOps.candidates(kind, data: env.store.data)
        if items.isEmpty {
            await dialogs.info(CrewScheduleText.pickTitle, CrewScheduleText.noItems(kind))
            return
        }
        let request = ItemPickerRequest(prompt: CrewScheduleText.pickPrompt(kind),
                                        rows: items.map { ItemPickerRow(display: $0.name, tag: $0.id) }, mode: .single)
        guard let picked = await dialogs.pickItems(request), let id = picked.first,
              let item = items.first(where: { $0.id == id }) else { return }
        title = item.name
        pendingRef = item.id
    }

    private func add(_ crew: CrewMember) async {
        guard let live = env.store.crewMember(id: crew.id) else { return }
        let entry = CrewScheduleOps.addEntry(to: live, title: title, kind: kind, refID: pendingRef,
                                             date: addDate?.civilDate, time: time, store: env.store)
        guard entry != nil else {
            await dialogs.info(CrewScheduleText.addEntryTitle, CrewScheduleText.addEntryEmpty)
            return
        }
        CrewPersist.save(env)
        title = ""
        pendingRef = nil
    }

    // MARK: BUILD-116…120 timeline

    private func timeline(_ crew: CrewMember) -> some View {
        let groups = CrewScheduleTimeline.groups(crew.schedule, today: env.clock.today())
        let byID = Dictionary(uniqueKeysWithValues: crew.schedule.map { ($0.id, $0) })
        return List {
            ForEach(groups) { g in
                Section {
                    ForEach(g.entryIDs, id: \.self) { id in
                        if let e = byID[id] {
                            CrewScheduleRow(entry: e,
                                            toggle: { e.done.toggle(); env.store.markDirty() },
                                            edit: { Task { await edit(e) } },
                                            delete: { delete(e, from: crew) })
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").foregroundStyle(AAColor.accent)
                        Text(g.label).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.accent)
                        Text("(\(g.count))").font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .overlay {
            if crew.schedule.isEmpty {
                AAEmptyState(title: "No Entries Yet", symbol: "calendar.badge.plus",
                             message: "Pick a date, choose what, and click Add.")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }

    /// BUILD-118 (prompt row 7 of the 06 Addendum caller registry: trim, blank = no-op, Save).
    private func edit(_ e: ScheduleEntry) async {
        let r = await dialogs.prompt(TextPromptRequest(title: CrewScheduleText.editEntryTitle,
                                                       prompt: CrewScheduleText.editEntryPrompt, initial: e.title))
        guard case .ok(let text) = r, CrewScheduleOps.editTitle(e, to: text) else { return }
        CrewPersist.save(env)
    }

    /// BUILD-119: immediate, no confirmation.
    private func delete(_ e: ScheduleEntry, from crew: CrewMember) {
        withAnimation(.snappy) { CrewScheduleOps.deleteEntry(e, from: crew, store: env.store) }
        CrewPersist.save(env)
    }

    // MARK: BUILD-121…124

    private func saveAs(_ crew: CrewMember) async {
        if crew.schedule.isEmpty {
            await dialogs.info(CrewScheduleText.saveTitle, CrewScheduleText.saveEmpty)
            return
        }
        let r = await dialogs.prompt(TextPromptRequest(title: CrewScheduleText.saveTitle,
                                                       prompt: CrewScheduleText.savePrompt, initial: crew.fullName))
        guard case .ok(let name) = r, !NetText.isBlank(name), let live = env.store.crewMember(id: crewID) else { return }
        let t = CrewScheduleOps.saveAsTemplate(live, name: name, store: env.store)
        CrewPersist.save(env)
        await dialogs.info(CrewScheduleText.saveTitle, CrewScheduleText.saved(t.name))
    }

    private func applySaved(_ crew: CrewMember) async {
        let templates = env.store.data.scheduleTemplates
        if templates.isEmpty {
            await dialogs.info(CrewScheduleText.applyTitle, CrewScheduleText.applyNone)
            return
        }
        let request = ItemPickerRequest(prompt: CrewScheduleText.applyPicker,
                                        rows: templates.map { ItemPickerRow(display: $0.display, tag: $0.id) },
                                        mode: .single)
        guard let picked = await dialogs.pickItems(request), let id = picked.first,
              let t = env.store.data.scheduleTemplates.first(where: { $0.id == id }) else { return }
        await confirmApply(t)
    }

    /// The BUILD-122 Yes / No / Cancel question as Replace / Append / Cancel.
    private func confirmApply(_ t: ScheduleTemplate) async {
        guard let crew = env.store.crewMember(id: crewID) else { return }
        let spec = AlertSpec(title: CrewScheduleText.applyTitle,
                             message: CrewScheduleText.applyQuestion(name: t.name, count: t.entries.count, crew: crew.fullName),
                             style: .informational,
                             buttons: [AlertButton(title: "Replace", role: .default), AlertButton(title: "Append"),
                                       AlertButton(title: "Cancel", role: .cancel)])
        let answer = await dialogs.alert(spec)
        guard answer == 0 || answer == 1, let live = env.store.crewMember(id: crewID) else { return }
        let n = CrewScheduleOps.apply(t, to: live, replace: answer == 0, store: env.store)
        CrewPersist.save(env)
        bind()
        await dialogs.info(CrewScheduleText.applyTitle, CrewScheduleText.applied(n, crew: live.fullName))
    }

    private func export(_ crew: CrewMember) async {
        if crew.schedule.isEmpty {
            await dialogs.info(CrewScheduleText.exportEmptyTitle, CrewScheduleText.exportEmpty)
            return
        }
        let config = SavePanelConfig(title: CrewScheduleText.exportPanelTitle,
                                     defaultName: CrewScheduleText.exportFileName(fullName: crew.fullName),
                                     allowedTypes: [.json], allowsOtherTypes: true)
        guard let url = await dialogs.savePanel(config), let live = env.store.crewMember(id: crewID) else { return }
        do {
            try CrewScheduleOps.export(live, to: url, store: env.store)
            await dialogs.info(CrewScheduleText.exportDoneTitle, CrewScheduleText.exported(url.path))
        } catch {
            await dialogs.error(CrewScheduleText.exportFailedTitle, CrewScheduleText.exportFailed(error.localizedDescription))
        }
    }

    private func importFile(_ crew: CrewMember) async {
        let urls = await dialogs.openPanel(OpenPanelConfig(message: CrewScheduleText.importPanelTitle,
                                                           allowedTypes: [.json], allFilesAccessory: true))
        guard let url = urls.first else { return }
        let t: ScheduleTemplate
        do {
            t = try CrewScheduleOps.importTemplate(contentsOf: url, store: env.store)
            try env.store.save()                                  // kept even if the apply is cancelled
        } catch {
            await dialogs.error(CrewScheduleText.importFailedTitle, CrewScheduleText.importFailed(error.localizedDescription))
            return
        }
        await confirmApply(t)
    }
}

/// BUILD-117: done check · time · kind icon · title (struck when done) · ✎ · ✕ (revealed on hover).
struct CrewScheduleRow: View {
    let entry: ScheduleEntry
    let toggle: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Toggle("", isOn: Binding(get: { entry.done }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(entry.time)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.muted)
                .frame(width: 46, alignment: .leading)
            Text(entry.kindIcon)
                .frame(width: 20)
                .accessibilityLabel(CrewScheduleText.kindName(entry.kind))
            AAStrikeText(entry.title, struck: entry.done)
                .font(.aaMono(AAType.small))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                Button(action: edit) { Image(systemName: "pencil") }
                    .help(CrewScheduleText.editHelp)
                    .accessibilityLabel(CrewScheduleText.editHelp)
                Button(action: delete) { Image(systemName: "xmark") }
                    .help(CrewScheduleText.deleteHelp)
                    .accessibilityLabel(CrewScheduleText.deleteHelp)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AAColor.muted)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            Button(action: edit) { Label("Edit Title…", systemImage: "pencil") }
            Button(role: .destructive, action: delete) { Label("Delete Entry", systemImage: "trash") }
        }
    }
}
