// Spec: 03 SHELL-001 (crash reporting), SHELL-197 (crash.log, fallback, signal marker, MetricKit on the next launch),
//       BD.3.5, §6.1 (Mac crash strategy), 01 DATA-004; ARCHITECTURE.md §9.2.
import AppKit
import MetricKit
import AACore

/// App-side crash sinks: uncaught Objective-C exceptions, the async-signal-safe marker, MetricKit payloads and the
/// next-launch dialog for a crash that the process could not survive.
@MainActor
enum ShellCrashReporter {
    nonisolated(unsafe) private static var appFolder: URL?
    private static var subscriber: ShellMetricKitSubscriber?
    /// A crash recorded by the previous session, shown once the main window exists.
    static var pendingNextLaunchReport: (message: String, path: URL)?

    static let scanOffsetKey = MacPreferences.Key("aa.shell.crashLogScanOffset")

    static func install(appFolder folder: URL?) {
        appFolder = folder
        CrashLog.installSignalMarker(appFolder: folder)
        NSSetUncaughtExceptionHandler(shellUncaughtExceptionHandler)
        scanForPreviousCrash(folder: folder)
    }

    /// Next launch: markers written since the last scan → the crash dialog after the main window appears.
    private static func scanForPreviousCrash(folder: URL?) {
        guard let folder else { return }
        let log = folder.appending(path: CrashLog.fileName)
        guard let data = try? Data(contentsOf: log) else { return }
        let prefs = MacPreferences.shared
        let stored = Int(prefs.string(scanOffsetKey) ?? "") ?? 0
        let start = stored <= data.count ? stored : 0
        let fresh = String(decoding: data[start...], as: UTF8.self)
        prefs.set(String(data.count), scanOffsetKey)
        if let sig = CrashLog.markers(in: fresh).last {
            pendingNextLaunchReport = ("AA quit unexpectedly the last time it ran (signal \(sig)).", log)
        }
    }

    static func startMetricKit() {
        let s = ShellMetricKitSubscriber()
        subscriber = s
        MXMetricManager.shared.add(s)
    }

    /// Shows the previous session's crash once (SHELL-197).
    static func presentPendingReport(env: AppEnvironment) async {
        guard let r = pendingNextLaunchReport else { return }
        pendingNextLaunchReport = nil
        await env.mainDialogs.error(CrashLog.dialogTitle, CrashLog.dialogMessage(message: r.message, writtenTo: r.path))
    }

    nonisolated static func recordException(_ e: NSException) {
        let details = CrashLog.details(exceptionName: e.name.rawValue, reason: e.reason, stack: e.callStackSymbols)
        CrashLog.append(details, appFolder: appFolder)
    }

    fileprivate static func recordDiagnostics(_ json: [String]) {
        guard !json.isEmpty else { return }
        let written = CrashLog.append("MetricKit crash diagnostic(s) from a previous session:\n" + json.joined(separator: "\n"),
                                      appFolder: appFolder)
        if let written, pendingNextLaunchReport == nil {
            pendingNextLaunchReport = ("macOS reported that AA crashed in a previous session.", written)
            if let env = LaunchCoordinator.shared.env, env.mainLoaded {
                Task { @MainActor in await presentPendingReport(env: env) }
            }
        }
    }
}

private func shellUncaughtExceptionHandler(_ e: NSException) {
    ShellCrashReporter.recordException(e)
}

final class ShellMetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let json = payloads.filter { !($0.crashDiagnostics ?? []).isEmpty }
            .map { String(decoding: $0.jsonRepresentation(), as: UTF8.self) }
        Task { @MainActor in ShellCrashReporter.recordDiagnostics(json) }
    }
}
