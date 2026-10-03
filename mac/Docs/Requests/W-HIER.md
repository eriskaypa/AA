# W-HIER — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-HIER-01: `check-ownership.sh` does not know `Docs/Progress/<agent-id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — `owner_of`, ARCHITECTURE.md §12.2; DECISIONS "Foundation requests"
(REQ-F1-01 ruling: each wave agent writes `Docs/Progress/<agent-id>.md`).
Need: `Docs/Progress/*.md` owned by the agent whose id is the file's basename (same rule as `Docs/Requests/*.md` and
`Docs/Deviations/*.md`, lines 54–57).
Why: the lead's ruling requires the file; the script reports it as an unowned path, so step 1/4 of the gate fails for
every wave agent that follows the ruling (build, tests, basenames and symbols are green).
Workaround in place: none possible inside W-HIER's paths; `Docs/Progress/W-HIER.md` is committed per the ruling and
is the only path the check flags.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)

## REQ-W-HIER-02: `ProcedureChecklistSection` cannot select a navigated step (DECISIONS 02 Q-11)
Target: ARCHITECTURE.md §7.7 row W-BUILD `ProcedureChecklistSection(procedureID: UUID)` (owner W-BUILD).
Need: an additive initializer `ProcedureChecklistSection(procedureID: UUID, revealStepID: UUID? = nil)` (or a
`Binding<UUID?>`) so a navigation request whose `childID` is a checklist step (search hit, quick switcher, Calendar
step row) selects and scrolls to that step, as DECISIONS 02 Q-11 requires.
Why: the hierarchy page receives `Navigator` requests with `childID` and fronts the Checklist tab, but the step grid
is W-BUILD's view and its published contract takes only the procedure id.
Workaround in place: the Procedures page selects the procedure, fronts the Checklist tab and consumes the child id;
subtasks (Tasks page) and components (Equipment page) are selected by W-HIER itself (nested subtasks select the
direct subtask that contains them).

Resolution: applied — `ProcedureChecklistSection(procedureID:revealStepID: Binding<UUID?> = .constant(nil))` selects and scrolls to a navigated step and consumes the request; HierProcedureSpecifics passes `model.pendingChildID` instead of discarding it; DECISIONS amendment (5742235)

## Additive API (no change requested)
Every contract of ARCH §6.8 (`TagParser`) and §7.7 (W-HIER rows) is implemented with the published signatures.
Additive public API in `Sources/AACore/Hierarchy/` (Hier-prefixed): `HierSidebarBuilder`, `HierText`, `HierPageOps`,
`HierUiState`, `HierRelations`, `HierGroupPicker`, `HierLinkPicker`, `HierLockForm`, `HierDuration`, `HierExportName`,
`HierCommandState`, `HierPageOps.directSubtask(of:revealing:)` / `component(of:id:)`, `TagParser.parseCommaOnly` / `isHashQuery`; additive AA initializer `ItemLockSheet(itemID:onFinish:)`.
