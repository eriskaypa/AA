// Spec: 03 SHELL-205 / BD.3.12 (automated launch smoke: real splash timer, real login model — a wrong password
//       first, then " 44233 " / redemption — real main-window load, real quit pipeline; JSON lines; exit 0 / 1 / 2 /
//       3), BD.4.7 (report), BD.4.8 (data folder afterwards), BD.7.6, Q-13 (kept in release builds), SHELL-177;
//       REQ-F3-01 (called by AAMain before the app runs: non-zero = refused and AAMain exits with it, 0 = armed).
import AppKit
import SwiftUI
import AACore

enum SmokeTest {
    /// Non-zero = refused (AAMain exits with it); 0 = the harness is armed and the launch continues.
    @MainActor static func run(options: LaunchOptions) -> Int32 {
        let fm = FileManager.default
        let resolved = AppFolderResolver.resolve(options, environment: ProcessInfo.processInfo.environment,
                                                 cwd: URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true),
                                                 home: fm.homeDirectoryForCurrentUser)
        var folder: URL?
        if case .success(let r) = resolved, r.source == .argument { folder = r.url }
        if let refusal = ShellXSmoke.refusal(dataDir: options.dataDir, appFolder: folder,
                                             fileExists: { fm.fileExists(atPath: $0) }) {
            FileHandle.standardError.write(Data((refusal + "\n").utf8))
            return ShellXSmoke.exitRefused
        }
        guard let folder else { return ShellXSmoke.exitRefused }
        ShellXSmokeHarness.shared.arm(appFolder: folder)
        return ShellXSmoke.exitOK
    }
}

/// Drives the live app through splash → login → main → autosave → quit and reports each step (BD.3.12).
@MainActor
final class ShellXSmokeHarness {
    static let shared = ShellXSmokeHarness()

    private var appFolder = URL(fileURLWithPath: "/")
    private let start = ContinuousClock.now
    private var splashAt: Double?
    private var finished = false
    private var quitObserver: NSObjectProtocol?

    /// Seconds since `AAMain` entry (monotonic).
    private var t: Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    func arm(appFolder: URL) {
        self.appFolder = appFolder
        let info = ShellXVersionInfo.current
        emit(ShellXSmoke.line("start", [("version", .string(info.reportVersion)), ("build", .string(info.reportBuild)),
                                         ("arch", .string(ShellLaunchEnvironment.architecture)),
                                         ("appFolder", .string(appFolder.path)), ("t", .seconds(t))]))
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShellXSmokeHarness.shared.didQuit() }
        }
        Task { @MainActor in await self.drive() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ShellXSmoke.watchdogSeconds))
            self.fail(step: "timeout", expected: "done within \(Int(ShellXSmoke.watchdogSeconds)) s",
                      actual: String(format: "%.3f s", self.t), code: ShellXSmoke.exitTimeout)
        }
    }

    // MARK: The drive

    private func drive() async {
        let opener = SceneOpener.shared
        // 1. Splash visible.
        await until { opener.window(for: .splash).map(Self.isVisible) ?? false }
        let splash = t
        splashAt = splash
        emit(ShellXSmoke.line("splash", [("t", .seconds(splash))]))

        // 2. Login visible; the splash lasted 2.3…2.9 s.
        await until { opener.window(for: .login).map(Self.isVisible) ?? false }
        let loginAt = t
        let splashSeconds = loginAt - splash
        emit(ShellXSmoke.line("login", [("t", .seconds(loginAt)), ("splashSeconds", .seconds(splashSeconds))]))
        guard ShellXSmoke.splashOK(splashSeconds) else {
            return fail(step: "login", expected: ShellXSmoke.splashExpectation,
                        actual: String(format: "%.3f", splashSeconds))
        }

        // 3. A wrong password is rejected and cleared.
        let model = ShellLoginModel.shared
        let accepted = model.submit(username: ShellXSmoke.username, password: ShellXSmoke.wrongPassword)
        guard !accepted, model.errorText == ShellLogin.failureMessage, model.password.isEmpty else {
            return fail(step: "login-rejected",
                        expected: "\(ShellLogin.failureMessage) and an empty password",
                        actual: accepted ? "accepted" : "\(model.errorText) / password \"\(model.password)\"")
        }
        emit(ShellXSmoke.line("login-rejected", [("message", .string(model.errorText))]))

        // 4. The real credentials (spaces prove the username Trim rule).
        await until { true }
        guard model.submit(username: ShellXSmoke.spacedUsername, password: ShellXSmoke.password) else {
            return fail(step: "login-accepted", expected: "44233 / redemption accepted", actual: model.errorText)
        }
        emit(ShellXSmoke.line("login-accepted", [("t", .seconds(t))]))

        // 5. Main window with data and the "Loaded — …" status.
        await until {
            guard let env = LaunchCoordinator.shared.env, env.mainLoaded,
                  let w = opener.window(for: .main), Self.isVisible(w) else { return false }
            return env.status.message.hasPrefix("Loaded — ")
        }
        guard let env = LaunchCoordinator.shared.env else {
            return fail(step: "main", expected: "main window", actual: "no environment")
        }
        let title = env.windowTitle
        let status = env.status.message
        emit(ShellXSmoke.line("main", [("t", .seconds(t)), ("title", .string(title)), ("status", .string(status))]))
        let expectedTitle = ShellXSmoke.expectedTitle(identity: env.settings.appIdentity)
        guard title == expectedTitle else { return fail(step: "main", expected: expectedTitle, actual: title) }
        let expectedStatus = ShellXSmoke.expectedStatus(appFolder: env.dataStore.appFolder)
        guard status == expectedStatus else { return fail(step: "main", expected: expectedStatus, actual: status) }

        // 6. The digest marks the data dirty; the 750 ms debounce writes data.json (≤ 3 s).
        let mainAt = t
        let dataFile = appFolder.appending(path: "data.json")
        var written: (bytes: Int, digest: String)?
        while t - mainAt <= ShellXSmoke.autosaveBudgetSeconds {
            if let w = Self.digestWrite(dataFile, expected: env.store.data.ui.lastDigestDate) { written = w; break }
            try? await Task.sleep(for: .milliseconds(ShellXSmoke.pollMilliseconds))
        }
        guard let written else {
            return fail(step: "autosaved", expected: "data.json with LastDigestDate within 3 s",
                        actual: FileManager.default.fileExists(atPath: dataFile.path) ? "no LastDigestDate" : "missing")
        }
        emit(ShellXSmoke.line("autosaved", [("t", .seconds(t)), ("bytes", .int(written.bytes)),
                                             ("lastDigestDate", .string(written.digest))]))

        // 7. The full close pipeline (SHELL-056); `quit` is reported from willTerminate.
        NSApp.terminate(nil)
        // terminate returns only when the quit was cancelled (an alert or sheet refused it).
        fail(step: "quit", expected: "the app terminates", actual: "termination was cancelled")
    }

    private func didQuit() {
        guard !finished else { return }
        finished = true
        emit(ShellXSmoke.line("quit", [("t", .seconds(t))]))
    }

    // MARK: Helpers

    /// `data.json` exists and carries the digest date the store holds (nil while not yet written).
    private static func digestWrite(_ url: URL, expected: String?) -> (bytes: Int, digest: String)? {
        guard let expected, let data = try? Data(contentsOf: url),
              case .object(let root)? = try? JSONParser.parse(data),
              case .object(let ui)? = root.rawValue(forKey: "Ui"),
              case .string(let digest)? = ui.rawValue(forKey: "LastDigestDate"), digest == expected else { return nil }
        return (data.count, digest)
    }

    /// On screen (ordered in). `occlusionState` is not required: it stays "occluded" while the display sleeps, the
    /// screen is locked or another Space is in front, which would make an unattended smoke run time out.
    private static func isVisible(_ w: NSWindow) -> Bool { w.isVisible }

    /// Polls `condition` every 50 ms (the watchdog bounds every wait).
    private func until(_ condition: @MainActor () -> Bool) async {
        while !condition() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func fail(step: String, expected: String, actual: String, code: Int32 = ShellXSmoke.exitFailed) {
        guard !finished else { return }
        finished = true
        emit(ShellXSmoke.failLine(step: step, expected: expected, actual: actual))
        exit(code)
    }
}
