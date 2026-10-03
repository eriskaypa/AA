// Spec: ARCHITECTURE.md §9.6 — W-FLASH's debug sheets for the snapshot hook (`--snapshot flash-sync --sheet <id>`):
//       w-flash.review-changeset, w-flash.review-snapshot, w-flash.review-bare-snapshot (FLASH-044/132/135).
//       The window itself is `--snapshot flash-sync`; DEBUG-only environment switches: AA_FLASH_DEBUG_TAB=receive,
//       AA_FLASH_DEBUG_AUTOSTART=1 (starts flashing so the plate shows a live code).
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_FLASH() {
        register("w-flash.review-changeset") { _ in
            AnyView(FlashReviewSheet(change: FlashDebugFixtures.changeSet) { _ in })
        }
        register("w-flash.review-snapshot") { _ in
            AnyView(FlashReviewSheet(change: FlashDebugFixtures.snapshot(withSettings: true)) { _ in })
        }
        register("w-flash.review-bare-snapshot") { _ in
            AnyView(FlashReviewSheet(change: FlashDebugFixtures.snapshot(withSettings: false)) { _ in })
        }
    }
}

enum FlashDebugFixtures {
    static var changeSet: FlashIncomingChange {
        let json = #"{"V":1,"From":"iOS","Created":"2026-09-27T12:00:00","Sets":{"Tasks":[{"Id":"a"},{"Id":"b"}],"Equipment":[{"Id":"e"}]},"Deletes":{"Tasks":["c"]},"Blocks":{"Log":[],"Sire":{}},"Order":{"Ports":["p1","p2"]},"BlockDeletes":["ObsoleteSection"],"Settings":{"DarkMode":true},"SettingsDeletes":["OldPreference"],"UiChanges":{"TabColors":{},"TabOrder":[]}}"#
        return FlashSyncStore.preview(Array(json.utf8), kind: .changeSet)
            ?? FlashIncomingChange(payload: JSONObject(), isSnapshot: false, summary: "other changes", carriesSettings: true)
    }

    static func snapshot(withSettings: Bool) -> FlashIncomingChange {
        let data = #"{"Equipment":[{"Id":"1"},{"Id":"2"}],"Tasks":[{"Id":"3"},{"Id":"4"},{"Id":"5"}],"Procedures":[],"Vessels":[{"Id":"v"}],"Crew":[],"Log":[],"Ports":[{"Id":"p"}],"Trash":[],"SchemaVersion":1,"Ui":{"TabOrder":[]}}"#
        let json = withSettings ? #"{"V":1,"Data":\#(data),"Settings":{"DarkMode":true}}"# : data
        return FlashSyncStore.preview(Array(json.utf8), kind: .fullSnapshot)
            ?? FlashIncomingChange(payload: JSONObject(), isSnapshot: true, summary: FlashChangeSet.snapshotSummary,
                                   carriesSettings: withSettings)
    }
}
#endif
