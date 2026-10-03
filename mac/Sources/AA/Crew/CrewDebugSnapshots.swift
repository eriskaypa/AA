// Debug snapshot registrations of W-CREW (ARCHITECTURE.md §9.6; sheet ids "w-crew.<name>"). Fixture data folder:
// Tests/AACoreTests/Fixtures/ui/w-crew/sample-data.json (copy it into a scratch folder as data.json).
//   AA --data-dir <dir> --snapshot CrewTab --out roster.png [--appearance dark]
//   AA --data-dir <dir> --snapshot crew-table --out table.png
//   AA --data-dir <dir> --snapshot CrewTab --sheet w-crew.editor --out editor.png   (also .editor-checklist / .editor-schedule)
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_CREW() {
        func editor(_ tab: CrewEditorTab) -> @MainActor (AppEnvironment) -> AnyView {
            { env in
                guard let m = env.store.data.crew.first else {
                    return AnyView(AAEmptyState(title: "No crew in the fixture", symbol: "person.3"))
                }
                return AnyView(CrewEditorSheet(memberID: m.id, initialTab: tab))
            }
        }
        register("w-crew.editor", editor(.details))
        register("w-crew.editor-checklist", editor(.checklist))
        register("w-crew.editor-schedule", editor(.schedule))
        // The lower part of the card of the member with the most review notes (notes + provenance).
        register("w-crew.card-notes") { env in
            guard let m = env.store.data.crew.max(by: { $0.flags.count < $1.flags.count }) else {
                return AnyView(AAEmptyState(title: "No crew in the fixture", symbol: "person.3"))
            }
            return AnyView(ScrollView {
                CrewCardView(member: m, today: env.clock.today()).padding(AASpacing.l)
            }
            .defaultScrollAnchor(.bottom)
            .frame(width: 720, height: 640)
            .background(AAColor.bg, ignoresSafeAreaEdges: []))
        }
    }
}
#endif
