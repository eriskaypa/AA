// Spec: 03 §6.8 (notification click → open the due-dates window), DECISIONS 02 Q-13, 10 Q7 (work-order notifications
//       open their target); ARCHITECTURE.md §7.3 ("Codable so a notification click can round-trip it through
//       `UNNotification.userInfo`, stored JSON-encoded under the key `aa.sceneRequest`"), §7.7 NotificationCenterBridge.
import Foundation

/// Round-trips a `Codable` click target (the AA target's `SceneRequest`) through a notification's `userInfo`:
/// JSON text under `aa.sceneRequest`, so the dictionary stays plist-safe for UserNotifications.
public enum ShellXNotificationPayload {
    public static let userInfoKey = "aa.sceneRequest"

    /// `[userInfoKey: json]`, or `[:]` for nil / an unencodable value.
    public static func userInfo<T: Encodable>(_ value: T?) -> [String: String] {
        guard let value, let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8)
        else { return [:] }
        return [userInfoKey: json]
    }

    /// The JSON text stored under `userInfoKey` (extracted first so no non-Sendable dictionary crosses actors).
    public static func json(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo[userInfoKey] as? String
    }

    /// Decodes the click target; nil when absent or not decodable as `T`.
    public static func decode<T: Decodable>(_ type: T.Type, json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
