// Spec: 13 §6.5 / DEV-FLASH-27 (frame n+1 is pre-rendered off-main while frame n is shown; at most one render in
//       flight), FLASH-013/020/023 and DEV-FLASH-04 (after a confirm, or an apply that drops a flashing stream, the
//       next prepared stream must flash normally).
// The bookkeeping of `FlashFrameSender`'s background render, as a value type so the "encoder replaced while a render
// is in flight" path is testable: a replaced stream starts a new generation AND frees the render slot, so the stale
// completion (which arrives later and is ignored) can never leave the slot taken for good.

/// One render slot per stream generation.
public struct FlashRenderGate: Sendable, Equatable {
    public private(set) var generation = 0
    public private(set) var rendering = false

    public init() {}

    /// A new stream (encoder replaced or cleared): bump the generation and free the slot. Any render still in flight
    /// belongs to the old generation; its completion is ignored by `complete(_:)`.
    public mutating func reset() {
        generation += 1
        rendering = false
    }

    /// Takes the slot; returns the generation the render belongs to, or nil when one is already in flight.
    public mutating func begin() -> Int? {
        guard !rendering else { return nil }
        rendering = true
        return generation
    }

    /// A render finished. Returns true when it belongs to the current stream (its result may be used) and frees the
    /// slot; a stale completion returns false and leaves the current stream's slot alone.
    public mutating func complete(_ gen: Int) -> Bool {
        guard gen == generation else { return false }
        rendering = false
        return true
    }
}
