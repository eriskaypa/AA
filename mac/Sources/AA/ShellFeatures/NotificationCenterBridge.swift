// Spec: 03 §6.8 (tray balloon → UserNotifications: authorisation requested lazily on the first reminder, fixed
//       identifier that replaces the previous one, `willPresent` → banner while AA is frontmost, click → due-dates
//       window), SHELL-130, SHELL-199 (unbundled runs never touch UNUserNotificationCenter — status-line fallback),
//       BD.3.12 (no authorisation requests during --smoke-test), 02 REPO-112, DECISIONS 02 Q-13, 10 Q7;
//       ARCHITECTURE.md §7.3 (`SceneRequest` round-trips through `userInfo["aa.sceneRequest"]`), §7.7, §9.3.
import AppKit
import SwiftUI
import UserNotifications
import AACore

@MainActor enum NotificationCenterBridge {
    /// False for unbundled runs (`swift run`: UNUserNotificationCenter raises without a bundle identifier) and during
    /// `--smoke-test` (no authorisation prompts, BD.3.12).
    static var isAvailable: Bool {
        !ShellLaunchEnvironment.isCurrentProcessUnbundled && !LaunchCoordinator.shared.options.smokeTest
            && !LaunchCoordinator.shared.snapshotMode
    }

    private static weak var env: AppEnvironment?
    private static let delegate = ShellXNotificationDelegate()
    private static var authorization: ShellXAuthorization = .unknown
    private static let log = AALog.logger("notifications")

    /// Called once by F3 at launch: installs the delegate (clicks, foreground banners). Never asks for permission —
    /// that happens lazily before the first notification.
    static func install(env: AppEnvironment) {
        self.env = env
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Posts (or replaces, same `id`) a notification. `onClick` is opened through `env.open` when the user clicks it.
    /// Unavailable → the status line shows `"{title}: {body}"` instead.
    static func post(id: String, title: String, body: String, onClick: SceneRequest?) {
        guard isAvailable else {
            env?.status.post("\(title): \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ShellXNotificationPayload.userInfo(onClick)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        Task { @MainActor in
            guard await ensureAuthorized() else {
                env?.status.post("\(title): \(body)")
                return
            }
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("notification \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                env?.status.post("\(title): \(body)")
            }
        }
    }

    /// Requests `.alert, .sound, .badge` once, the first time a notification would be posted (03 §6.8).
    private static func ensureAuthorized() async -> Bool {
        switch authorization {
        case .granted: return true
        case .denied: return false
        case .unknown:
            do {
                let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                authorization = ok ? .granted : .denied
                return ok
            } catch {
                log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
                authorization = .denied
                return false
            }
        }
    }

    /// The click handler: decodes the `SceneRequest` and opens it (the due-dates panel for reminders).
    fileprivate static func handleClick(json: String?) {
        NSApp.activate()
        guard let env else { return }
        if let request = ShellXNotificationPayload.decode(SceneRequest.self, json: json) {
            if case .dueDates = request {} else { env.showMainWindow() }
            env.open(request)
        } else {
            env.showMainWindow()
        }
    }
}

private enum ShellXAuthorization { case unknown, granted, denied }

/// `UNUserNotificationCenterDelegate`: banners while AA is frontmost (Windows balloons show regardless) and clicks.
final class ShellXNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let json = ShellXNotificationPayload.json(from: response.notification.request.content.userInfo)
        completionHandler()
        Task { @MainActor in NotificationCenterBridge.handleClick(json: json) }
    }
}
