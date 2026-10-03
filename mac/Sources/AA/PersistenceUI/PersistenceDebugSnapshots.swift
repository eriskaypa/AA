// Spec: ARCHITECTURE.md §9.6 — W-PERSIST's debug sheets (ids "w-persist.<name>"): the DATA-180 sheet in its three
//       variants, the DATA-181 conflict-copies list (reads the scratch data folder's conflicts/), the File Links
//       settings with an in-memory table, and the DATA-174/175/180/184 banners.
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_PERSIST() {
        register("w-persist.conflict-changed") { _ in
            AnyView(DataFileConflictSheet(conflict: DataFileConflict(
                kind: .changed, fileName: "data.json", ourTime: "2026-09-30 14:12:40", theirTime: "2026-09-30 14:15:02",
                theirBytes: Data("{}".utf8))) { _ in })
        }
        register("w-persist.conflict-unreadable") { _ in
            AnyView(DataFileConflictSheet(conflict: DataFileConflict(
                kind: .unreadable(reason: "it was encrypted by AA on Windows"), fileName: "data.json",
                ourTime: "2026-09-30 14:12:40", theirTime: PersistConflictText.noSaveDate,
                theirBytes: LocalEncryption.windowsMagic)) { _ in })
        }
        register("w-persist.conflict-deleted") { _ in
            AnyView(DataFileConflictSheet(conflict: DataFileConflict(
                kind: .deleted, fileName: "data.json", ourTime: "2026-09-30 14:12:40",
                theirTime: PersistConflictText.noSaveDate, theirBytes: nil)) { _ in })
        }
        register("w-persist.conflict-copies") { _ in AnyView(ConflictCopiesSheet()) }
        register("w-persist.path-mappings") { _ in
            let m = PathMapper()
            m.mappings = [PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ship"),
                          PathMapping(windowsPrefix: "\\\\bridge-nas\\manuals", macPath: "smb://bridge-nas/manuals"),
                          PathMapping(windowsPrefix: "S:\\Cargo\\Plans", macPath: NSHomeDirectory() + "/Documents")]
            return AnyView(PathMappingSettingsView(mapper: m, probe: "S:\\Cargo\\Plans")
                .frame(width: 640, height: 470)
                .aaSheet(.closeType))
        }
        register("w-persist.path-mappings-empty") { _ in
            AnyView(PathMappingSettingsView(mapper: PathMapper(), probe: "")
                .frame(width: 640, height: 470)
                .aaSheet(.closeType))
        }
        register("w-persist.path-mappings-unc") { _ in
            AnyView(PathMappingSettingsView(mapper: PathMapper(), probe: "\\\\engine-pc\\drawings\\P&ID.pdf")
                .frame(width: 640, height: 470)
                .aaSheet(.closeType))
        }
        register("w-persist.path-mapping-editor") { _ in
            let draft = PersistMappingDraft(PathMapping(windowsPrefix: "\\\\bridge-nas\\manuals",
                                                        macPath: "/Volumes/manuals"))
            return AnyView(PersistMappingEditor(draft: draft) { _ in })
        }
        register("w-persist.path-mapping-invalid") { _ in
            var draft = PersistMappingDraft()
            draft.windowsPrefix = "manuals"
            draft.macPath = "/Volumes/Ship"
            return AnyView(PersistMappingEditor(draft: draft) { _ in })
        }
        register("w-persist.banners") { _ in
            AnyView(PersistBannerGallery().aaSheet(.closeType))
        }
    }
}

/// Every W-PERSIST banner state, stacked (snapshot only).
struct PersistBannerGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text("Banners").font(.system(size: 14, weight: .bold)).padding([.top, .horizontal], AASpacing.m)
            PersistReadOnlyBannerContent(phase: .readOnly, canSwitch: true, onSwitch: {}, onEditHere: {}, onStay: {},
                                         onConflictCopies: {})
            PersistReadOnlyBannerContent(phase: .canEdit, canSwitch: true, onSwitch: {}, onEditHere: {}, onStay: {},
                                         onConflictCopies: {})
            PersistStoppedBannerContent(onResume: {}, onConflictCopies: {})
            PersistWindowsBannerContent(onShowMe: {}, onDontShow: {})
            Spacer(minLength: 0)
        }
        .frame(width: 900, height: 420, alignment: .top)
    }
}
