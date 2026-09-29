// Spec: 01 §4.2 (IJob, IBucketable); ARCHITECTURE.md §4.1.
import Foundation

/// C# `IJob` — TaskItem (incl. subtasks), Procedure, ChecklistStep. (Not `Job`: clashes with `_Concurrency.Job`.)
@MainActor public protocol SchedulableJob: AnyObject {
    var id: UUID { get }
    var isJob: Bool { get set }
    var durationMinutes: Int { get set }
    var scheduledStart: NetDateTime? { get set }
    var jobName: String { get }
}

/// C# `IBucketable` — HierarchyItem, ChecklistStep.
@MainActor public protocol Bucketable: AnyObject {
    var bucketIds: [UUID] { get set }
}
