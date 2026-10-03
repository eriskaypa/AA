// Spec: ARCHITECTURE.md §6.1, §11 — W-PLAN's contract flag, read by `ContractStatus.isImplemented(.wPlan)`.
// AACore/Calendar and AACore/Board hold W-PLAN's real logic (CalendarRowBuilder, PlannerGeometry, PlannerPlacement,
// BoardModel, BoardSavedListAdd, BucketsModel, MapLayout).
extension ContractStatus { public static let wPlanImplemented = true }
