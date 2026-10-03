// Spec: 12 SIRE-001/002/003 (lazy, process-wide, cached failure until restart), §3.5 (SireBank), §6.1, §6.8 (the
//       export awaits a running load), ARCHITECTURE.md §2.2 (decode off the main actor; Sendable results),
//       §9.5 (resource via `AAResources` only).
import Foundation
import Observation

/// The process-wide SIRE bank cache. The first `load()` parses the bundled JSON in a detached task; every later
/// call (and every concurrent caller) shares the same result. A failure is cached until the app restarts.
@MainActor @Observable
public final class SireBank {
    public static let shared = SireBank()

    public enum Phase: Equatable {
        case notLoaded, loading, loaded, failed(String)
    }

    public private(set) var phase: Phase = .notLoaded
    public private(set) var contents: SireBankContents?
    /// `LoadError` (nil while loaded or never loaded).
    public var loadError: String? { if case .failed(let m) = phase { return m }; return nil }
    public var isLoaded: Bool { phase == .loaded }

    @ObservationIgnored private var inFlight: Task<Result<SireBankContents, SireBankError>, Never>?
    @ObservationIgnored private let source: @Sendable () -> Data?

    /// `source` returns the raw bank bytes (nil = resource missing). The default reads the bundled resource.
    public init(source: @escaping @Sendable () -> Data? = { AAResources.data(name: "sire2_question_bank", ext: "json") }) {
        self.source = source
    }

    /// Loads once per process (SIRE-001); returns the cached contents or the cached error.
    @discardableResult
    public func load() async -> Result<SireBankContents, SireBankError> {
        switch phase {
        case .loaded: if let contents { return .success(contents) }
        case .failed(let m): return .failure(.invalid(m))
        case .notLoaded, .loading: break
        }
        if let inFlight { return await inFlight.value }
        phase = .loading
        let src = source
        // The in-flight task publishes `contents` / `phase` itself BEFORE it returns, so every waiter — the first
        // caller and any concurrent one (the export sheet opened while the tab is loading, §6.8 / Q-10) — resumes
        // only after the state is final, whatever order the runtime resumes them in.
        let task = Task { @MainActor [weak self] () -> Result<SireBankContents, SireBankError> in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SireBankContents, SireBankError> in
                guard let data = src() else { return .failure(.notFound) }
                do throws(SireBankError) { return .success(try SireBankDecoder.load(data)) } catch { return .failure(error) }
            }.value
            self?.publish(result)
            return result
        }
        inFlight = task
        return await task.value
    }

    private func publish(_ result: Result<SireBankContents, SireBankError>) {
        switch result {
        case .success(let c):
            contents = c
            phase = .loaded
        case .failure(let e):
            contents = SireBankContents()                     // _questions = new(), _identified = new()
            phase = .failed(e.localizedDescription)
        }
        inFlight = nil
    }

    /// Test / preview hook: installs already-built contents (no resource read).
    public func install(_ c: SireBankContents) {
        contents = c
        phase = .loaded
    }
}
