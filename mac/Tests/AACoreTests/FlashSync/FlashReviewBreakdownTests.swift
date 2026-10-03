// TV: 13 FLASH-135 (rich review breakdown: sets / deletes / blocks / removals / settings / layout, excluded and
//     per-device keys never listed), FLASH-132 (snapshot without settings says so).
import Foundation
import Testing
@testable import AACore

@Suite struct FlashReviewBreakdownTests {
    static func change(_ json: String, kind: FlashFrameKind) -> FlashIncomingChange {
        FlashSyncStore.preview(Array(json.utf8), kind: kind)!
    }

    @Test func changeSetRows() {
        let c = Self.change(#"{"V":1,"Sets":{"Tasks":[{"Id":"a"},{"Id":"b"}],"Ui":[{"Id":"x"}]},"Deletes":{"Crew":["c"]},"Order":{"Ports":["p"]},"Blocks":{"Log":[],"Ui":{"TabOrder":[],"WindowLeft":1}},"UiChanges":{"TabColors":{},"SelectedTaskId":"q"},"UiDeletes":["SortAZ","WindowTop"],"BlockDeletes":["Old","LastModified"],"Settings":{"DarkMode":true,"PasswordHash":"x"},"SettingsDeletes":["Foo","PasswordSalt"]}"#, kind: .changeSet)
        let rows = FlashReviewBreakdown.rows(for: c).map { "\($0.title)|\($0.detail)|\($0.tone)" }
        #expect(rows == [
            "Tasks|2 items added or changed|added",
            "Crew|1 item deleted|removed",
            "Ports|reordered|changed",
            "Log|replaced as a whole|changed",
            "Layout|2 preferences changed, 1 removed|changed",
            "Old|REMOVED entirely|removed",
            "Settings|1 setting merged|changed",
            "Settings|clears 1 setting|removed",
        ])
    }

    @Test func snapshotRows() {
        let withSettings = Self.change(#"{"V":1,"Data":{"Tasks":[{"Id":"1"}],"Log":[],"Ui":{"TabOrder":[]},"SchemaVersion":1},"Settings":{"DarkMode":true,"AppIdentity":"PC"}}"#, kind: .fullSnapshot)
        let rows = FlashReviewBreakdown.rows(for: withSettings).map { "\($0.title)|\($0.detail)" }
        #expect(rows == ["Whole database|replaces everything on this Mac", "Tasks|1 item", "Log|0 items",
                         "Layout|shared preferences replaced; this Mac's window layout kept", "Settings|1 setting merged"])
        let bare = Self.change(#"{"Tasks":[]}"#, kind: .fullSnapshot)
        #expect(FlashReviewBreakdown.rows(for: bare).last?.detail == "not carried — dark mode etc. stay as they are")
        #expect(FlashReviewBreakdown.rows(for: Self.change(#"{"V":1}"#, kind: .changeSet)).map(\.title) == ["Other changes"])
    }
}
