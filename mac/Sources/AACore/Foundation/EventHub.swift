// Spec: 02 REPO-007 (Saved event), ARCHITECTURE.md §5.2 (EventHub + isolated deinit).
import Foundation

/// A main-actor multicast event. Subscribers are called in subscription order.
@MainActor public final class EventHub<Payload> {
    private var handlers: [(id: Int, fn: @MainActor (Payload) -> Void)] = []
    private var nextID = 0

    public init() {}

    /// Registers `handler`. **Keep the returned subscription**: the subscription ends when the token is cancelled
    /// or released (including when the result is discarded).
    @discardableResult
    public func subscribe(_ handler: @escaping @MainActor (Payload) -> Void) -> EventSubscription {
        let id = nextID
        nextID += 1
        handlers.append((id: id, fn: handler))
        return EventSubscription { [weak self] in self?.remove(id) }
    }

    public func send(_ payload: Payload) {
        let snapshot = handlers
        for h in snapshot where handlers.contains(where: { $0.id == h.id }) { h.fn(payload) }
    }

    public func removeAll() { handlers.removeAll() }

    /// Number of live subscriptions (tests).
    public var subscriberCount: Int { handlers.count }

    private func remove(_ id: Int) { handlers.removeAll { $0.id == id } }
}

@MainActor public final class EventSubscription {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }

    public func cancel() {
        let c = onCancel
        onCancel = nil
        c?()
    }

    isolated deinit { cancel() }
}
