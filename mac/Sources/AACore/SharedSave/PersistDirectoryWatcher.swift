// Spec: 01 §6.9 (watch the bundle's DIRECTORY with O_EVTONLY + DispatchSource — the atomic rename replaces the
//       file's vnode; .write/.rename/.delete/.extend/.attrib/.link; the handler only restarts the 1.5 s debounce;
//       re-arm when the directory disappears/reappears), DATA-053, DATA-174 (live view), DATA-180 step 3 (data-file
//       watcher, 1.5 s debounce, 60 s poll on network volumes); ARCHITECTURE.md §6.6 ("DirectoryWatcher").
import Foundation
import Darwin

/// A best-effort directory watcher with a debounce, an optional unconditional poll and automatic re-arming.
/// Every callback runs on the main actor.
@MainActor public final class PersistDirectoryWatcher {
    public let directory: URL
    public let debounce: Duration
    /// nil = no unconditional poll (the owner runs its own).
    public let poll: Duration?
    /// How often a dead watcher (directory missing, VPN/VSAT drop) tries to re-arm.
    public var rearmInterval: Duration = .seconds(5)

    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var rearmTask: Task<Void, Never>?
    private(set) public var isRunning = false

    public init(directory: URL, debounce: Duration = .milliseconds(1500), poll: Duration? = nil,
                onChange: @escaping @MainActor () -> Void) {
        self.directory = directory; self.debounce = debounce; self.poll = poll; self.onChange = onChange
    }

    /// True while the kernel source is armed (false when the directory could not be opened).
    public var isArmed: Bool { source != nil }

    public func start() {
        stop()
        isRunning = true
        arm()
        if let poll {
            pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: poll)
                    guard !Task.isCancelled, let self, self.isRunning else { return }
                    self.onChange()
                }
            }
        }
        rearmTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.rearmInterval else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, self.isRunning else { return }
                if self.source == nil {
                    self.arm()
                    if self.source != nil { self.fire() }               // the directory came back: check now
                }
            }
        }
    }

    public func stop() {
        isRunning = false
        source?.cancel()
        source = nil
        debounceTask?.cancel(); debounceTask = nil
        pollTask?.cancel(); pollTask = nil
        rearmTask?.cancel(); rearmTask = nil
    }

    /// Restarts the debounce (what every kernel event does).
    public func fire() {
        debounceTask?.cancel()
        let d = debounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: d)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.onChange()
        }
    }

    private func arm() {
        let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ev = self.source?.data ?? []
                if ev.contains(.delete) || ev.contains(.rename) {
                    // The directory itself went away (or moved): drop the source; the re-arm loop reopens it.
                    self.source?.cancel()
                    self.source = nil
                }
                self.fire()
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }
}
