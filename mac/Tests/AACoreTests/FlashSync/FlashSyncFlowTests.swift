// TV: 13 §7.10 (EstimateSeconds, progress text, summary pluralisation), FLASH-011…020 (Send state machine), FLASH-030…048
//     (Receive state machine incl. the Q-7 Rescan fix and the single-apply guard), DECISIONS 13 Q-4 (stale encoder
//     cleared), 03 SHELL-676 / T-KB-46 (⌘. / ⎋ stops flashing, window stays) and T-KB-47 (idle ⎋ does nothing),
//     FLASH-044/132 (review text), SHELL-199 (unbundled camera text).
import Foundation
import Testing
@testable import AACore

@Suite struct FlashSyncFlowTests {
    // TV: 13 §7.10 EstimateSeconds
    @Test func estimates() {
        #expect(FlashSyncTexts.estimate(chunks: 1, fps: 12) == "2 seconds")
        #expect(FlashSyncTexts.estimate(chunks: 486, fps: 12) == "56 seconds")
        #expect(FlashSyncTexts.estimate(chunks: 486, fps: 6) == "1 min 51 s")
        #expect(FlashSyncTexts.estimate(chunks: 180, fps: 9) == "29 seconds")      // C# double rounding of 1.35
        #expect(FlashSyncTexts.estimate(chunks: 5, fps: 0) == "2 seconds")         // fps ≤ 0 → 12
    }

    // TV: 13 §7.10 progress text and summary pluralisation
    @Test func progressAndSummaries() {
        #expect(FlashSyncTexts.flashingProgress(framesShown: 1, chunks: 2) == "Flashing — 1 frames shown, 0 full passes. Keep going until the iPhone says it is done.")
        #expect(FlashSyncTexts.flashingProgress(framesShown: 2, chunks: 2).contains("1 full pass."))
        #expect(FlashSyncTexts.flashingProgress(framesShown: 5, chunks: 2).contains("2 full passes."))
        #expect(FlashSyncTexts.changeSetSummary(label: "1 Tasks", chunks: 1, fps: 12) == "Sending your changes since the last confirmed transfer — 1 Tasks. 1 piece, about 2 seconds.")
        #expect(FlashSyncTexts.changeSetSummary(label: "x", chunks: 2, fps: 12).contains("2 pieces,"))
        #expect(FlashSyncTexts.snapshotSummary(chunks: 1, fps: 12) == "First transfer to this iPhone, so the whole database goes across: 1 pieces, about 2 seconds.")
        #expect(FlashSyncTexts.fpsText(12) == "12 / sec")
    }

    // TV: FLASH-011…020, T-KB-46/47
    @Test func sendFlow() {
        var f = FlashSendFlow()
        #expect(f.fps == 12 && !f.startEnabled && !f.stopEnabled && !f.confirmEnabled)
        var idle = f
        let idleStopped = idle.stopCommand()
        #expect(!idleStopped)                                                // T-KB-47: idle ⎋ does nothing
        #expect(idle == f)
        f.didPrepare(kind: .changeSet, label: "2 Tasks", chunks: 3)
        #expect(f.startEnabled && f.summaryText.hasPrefix("Sending your changes since the last confirmed transfer — 2 Tasks. 3 pieces"))
        let m1 = f.start()
        #expect(m1)
        #expect(f.isFlashing && f.stopEnabled && f.confirmEnabled && !f.startEnabled && !f.canRePrepare)
        for _ in 0 ..< 7 { f.frameShown() }
        #expect(f.progressText.hasPrefix("Flashing — 7 frames shown, 2 full passes."))
        let stopped = f.stopCommand()
        #expect(stopped)                                                     // T-KB-46: ⌘. / ⎋ stops flashing
        #expect(!f.isFlashing && f.confirmEnabled && f.startEnabled)         // confirm stays; Start continues
        #expect(f.framesShown == 7)
        f.fps = 6
        #expect(f.summaryText.contains("about 2 seconds"))                   // Q-8: live estimate
        f.fps = 99
        #expect(f.fps == 15)
        f.fps = 12
        f.didConfirm()
        #expect(!f.hasPayload && !f.confirmEnabled && f.progressText == "")
        f.didFindNothingToSend()
        #expect(f.summaryText == FlashSyncTexts.nothingToSend && !f.startEnabled)
        // Q-4: a stale stream is dropped when the re-prepare finds nothing.
        f.didPrepare(kind: .fullSnapshot, label: "full database", chunks: 486)
        #expect(f.summaryText == "First transfer to this iPhone, so the whole database goes across: 486 pieces, about 56 seconds.")
        f.start()
        f.didFindNothingToSend()
        #expect(!f.isFlashing && !f.confirmEnabled && !f.startEnabled)
        f.didFail(FlashSyncError.databaseUnreadableMessage)
        #expect(f.summaryText == "The database could not be read, so Flash Sync is unavailable until it is fixed." && !f.startEnabled)
    }

    // TV: FLASH-030…048, Q-7
    @Test func receiveFlow() {
        var r = FlashReceiveFlow()
        r.setAccess(.granted)
        r.camerasListed([])
        #expect(r.statusText == "No camera found. Plug one in and press Rescan — or use the Send tab, which needs no camera at all.")
        #expect(!r.startEnabled && r.rescanEnabled)
        r.camerasListed(["FaceTime HD Camera", "iPhone Camera"], preferred: 1)
        #expect(r.selectedCamera == 1 && r.startEnabled && r.statusText == "")
        r.cameraStarting()
        #expect(r.isCapturing && !r.startEnabled && r.stopEnabled && !r.rescanEnabled && !r.pickerEnabled)
        #expect(r.statusText == FlashSyncTexts.looking)
        let m2 = r.progressed(solved: 0, total: 0, label: "", complete: false)
        #expect(!m2)
        #expect(r.statusText == FlashSyncTexts.looking)
        let m3 = r.progressed(solved: 2, total: 5, label: "3 Tasks", complete: false)
        #expect(!m3)
        #expect(r.statusText == "Receiving — 2 of 5 pieces. Hold steady." && r.labelText == "Incoming: 3 Tasks")
        let m4 = r.progressed(solved: 3, total: 5, label: "  ", complete: false)
        #expect(!m4)
        #expect(r.labelText == "Incoming: 3 Tasks")                          // blank label leaves the line
        let m5 = r.progressed(solved: 5, total: 5, label: "3 Tasks", complete: true)
        #expect(m5)
        let again = r.progressed(solved: 5, total: 5, label: "3 Tasks", complete: true)
        #expect(!again)                                                      // a second completion is ignored
        #expect(r.isApplying && !r.isCapturing && !r.startEnabled)
        r.finished(.discarded)
        #expect(r.statusText == "Discarded — nothing was changed." && r.startEnabled)
        r.cameraStarting()
        let m6 = r.stopCommand()
        #expect(m6 && !r.isCapturing)
        let m7 = r.stopCommand()
        #expect(!m7)
        r.cameraStarting()
        r.cameraFailed(FlashSyncTexts.cameraStoppedSending)
        #expect(!r.isCapturing && r.statusText == "The camera stopped sending frames." && r.statusIsProblem)
        r.finished(.applied(summary: "1 Tasks"))
        #expect(r.statusText == "Applied. 1 Tasks")
        r.finished(.failed)
        #expect(r.statusText == "Failed to apply — your data was not changed.")
        r.finished(.damaged)
        #expect(r.statusText == "The transfer arrived damaged, so nothing was changed. Start the iPhone sending again.")
        r.finished(.unreadable)
        #expect(r.statusText == "That transfer was not readable as Flash Sync data. Nothing was changed.")
    }

    // TV: SHELL-199 / 13 §6.4 — unbundled and denied camera states
    @Test func cameraAccessStates() {
        var r = FlashReceiveFlow()
        r.setAccess(.unbundled)
        r.camerasListed(["FaceTime HD Camera"])
        #expect(r.statusText == "The camera needs the packaged app. Build it with Scripts/build-app.sh and open dist/AA.app.")
        #expect(!r.startEnabled && !r.rescanEnabled)
        var d = FlashReceiveFlow()
        d.setAccess(.denied)
        d.camerasListed([])
        #expect(d.statusText == "Camera access is turned off for AA. Allow it in System Settings ▸ Privacy & Security ▸ Camera.")
        #expect(!d.startEnabled)
    }

    // TV: DEV-FLASH-26 / FLASH-030/033 — camera allowed in System Settings after a denial: the denied text clears and
    //     Start camera enables again (the window re-reads the authorization on Rescan / becoming key)
    @Test func cameraAccessGrantedAfterDenial() {
        var r = FlashReceiveFlow()
        r.setAccess(.denied)
        r.camerasListed(["FaceTime HD Camera"])
        #expect(!r.startEnabled && r.statusIsProblem)
        r.setAccess(.granted)
        r.camerasListed(["FaceTime HD Camera"])
        #expect(r.startEnabled)
        #expect(r.statusText == "" && !r.statusIsProblem)
        // Another status survives a re-grant (only the denied text is cleared).
        var n = FlashReceiveFlow()
        n.setAccess(.granted)
        n.camerasListed([])
        n.setAccess(.granted)
        #expect(n.statusText == FlashSyncTexts.noCamera)
    }

    // TV: 13 §6.5 / DEV-FLASH-27 — the encoder is replaced while a render is in flight (confirm, or an apply that
    //     drops the flashing stream): the new stream renders at once and the stale completion is ignored
    @Test func renderGateSurvivesAReplacedEncoder() {
        var g = FlashRenderGate()
        let old = g.begin()
        let second = g.begin()
        #expect(old != nil && second == nil)                 // one render at a time
        g.reset()                                            // setEncoder(nil)
        g.reset()                                            // setEncoder(new)
        let fresh = g.begin()
        #expect(fresh != nil && fresh != old)                // not blocked by the abandoned render
        let staleUsed = g.complete(old ?? -1)                // the stale completion arrives late: ignored…
        #expect(!staleUsed)
        #expect(g.rendering)                                 // …and does not free the new stream's slot
        let freshUsed = g.complete(fresh ?? -1)
        #expect(freshUsed && !g.rendering)
        let next = g.begin()
        #expect(next != nil)                                 // and the stream keeps going
    }

    // TV: FLASH-044 / FLASH-132 review text
    @Test func reviewText() {
        let cs = FlashIncomingChange(payload: JSONObject(), isSnapshot: false, summary: "2 Tasks, layout", carriesSettings: true)
        #expect(FlashSyncTexts.applyQuestion(cs) == "Received from the iPhone:\n\n    2 Tasks, layout\n\nApply it now?")
        let snap = FlashIncomingChange(payload: JSONObject(), isSnapshot: true, summary: FlashChangeSet.snapshotSummary, carriesSettings: true)
        #expect(FlashSyncTexts.applyQuestion(snap) == "Received from the iPhone:\n\n    the sender's entire database (replaces yours)\n\nThis REPLACES your current database with the iPhone's copy. Anything on this Mac that is not on the phone will be lost.\n\nApply it now?")
        let bare = FlashIncomingChange(payload: JSONObject(), isSnapshot: true, summary: FlashChangeSet.snapshotSummary, carriesSettings: false)
        #expect(FlashSyncTexts.applyQuestion(bare).hasSuffix("will be lost.\n\nThis copy carries no settings (dark mode etc. stay as they are).\n\nApply it now?"))
    }
}
