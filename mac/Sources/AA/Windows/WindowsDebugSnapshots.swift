// Spec: ARCHITECTURE.md §9.6 — W-QUICK's debug sheets for the snapshot hook (`--sheet w-quick.<name>`), built from the
//       loaded fixture (`Tests/AACoreTests/Fixtures/ui/w-quick/`). The windows themselves are snapshot targets
//       (`quick-work`, `due`, `switcher`, `search`, `activity-log`); `--select <uuid>` pre-selects a quick-work item.
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_QUICK() {
        register("w-quick.trash") { _ in AnyView(TrashSheet()) }
        register("w-quick.review") { env in
            AnyView(ReviewChangesSheet(request: WindowsDebugFixtures.reviewRequest(env: env)) { _ in })
        }
        register("w-quick.review-empty") { env in
            let same = ModelCodec.deepClone(env.store.data)
            let req = ReviewChangesRequest(sourceName: "Google Drive (newer save)",
                                           ageText: AgeVerdict.text(incoming: same.lastModified, current: env.store.data.lastModified),
                                           diff: DataDiff.compare(current: env.store.data, incoming: same),
                                           otherData: DataDiff.compareOtherData(current: env.store.data, incoming: same))
            return AnyView(ReviewChangesSheet(request: req) { _ in })
        }
        register("w-quick.search") { _ in
            AnyView(SearchWindowView(initialQuery: "pump").frame(width: 900, height: 560))
        }
        register("w-quick.switcher") { env in
            let model = SwitcherModel(rows: QuickSwitcherScoring.rows(store: env.store, isGated: env.locks.isGated),
                                      query: "#safety")
            return AnyView(SwitcherView(model: model, onOpen: { _ in }, onClose: {}).frame(width: 620, height: 420))
        }
        register("w-quick.switcher-pump") { env in
            let model = SwitcherModel(rows: QuickSwitcherScoring.rows(store: env.store, isGated: env.locks.isGated),
                                      query: "pump")
            return AnyView(SwitcherView(model: model, onOpen: { _ in }, onClose: {}).frame(width: 620, height: 420))
        }
    }
}

/// Builds a realistic incoming copy of the loaded data for the review-sheet snapshot.
@MainActor enum WindowsDebugFixtures {
    static func reviewRequest(env: AppEnvironment) -> ReviewChangesRequest {
        let current = env.store.data
        let incoming = ModelCodec.deepClone(current)
        if let t = incoming.tasks.first {
            t.deadline = (t.deadline ?? NetDateTime.calendarDate(env.clock.today())).addingDays(4)
            t.status = .inProgress
            t.description = "Coordinate with class surveyor; divers booked for Tuesday morning."
            if let s = t.subtasks.last { s.name += " (rev. B)" }
        }
        if incoming.procedures.count > 1 { incoming.procedures.remove(at: incoming.procedures.count - 1) }
        if let p = incoming.procedures.first, let s = p.steps.dropFirst().first { s.done.toggle() }
        if let e = incoming.equipment.first {
            e.components.first?.container.files.append(FileItem(name: "TC overhaul report.pdf",
                                                                path: "files/1f2e3d4c5b6a79880011223344556677_TC overhaul report.pdf"))
        }
        let added = TaskItem(name: "Prepare port state control checklist")
        added.subtasks = [TaskItem(name: "Certificates folder"), TaskItem(name: "Oil record book")]
        incoming.tasks.append(added)
        let crew = CrewMember(); crew.firstName = "Joana"; crew.lastName = "Pereira"
        incoming.crew.append(crew)
        incoming.lastModified = (current.lastModified ?? env.clock.now()).addingTicks(NetDateTime.ticksPerDay + 3_600 * NetDateTime.ticksPerSecond)
        return ReviewChangesRequest(sourceName: "aa-backup-2026-10-03.aaz",
                                    ageText: AgeVerdict.text(incoming: incoming.lastModified, current: current.lastModified),
                                    diff: DataDiff.compare(current: current, incoming: incoming),
                                    otherData: DataDiff.compareOtherData(current: current, incoming: incoming))
    }
}
#endif
