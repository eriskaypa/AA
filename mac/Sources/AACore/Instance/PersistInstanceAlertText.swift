// Spec: 01 DATA-172 (second-launch alert: messageText, informativeText with {holder}/{folder}/{choice}, stale-claim
//       line, buttons and defaults), DATA-179 (external-file variant), MP.7.1 G-1, MP.7.2 F-3, MP.7.3 (lease buttons).
import Foundation

/// The DATA-172 / DATA-179 alert, computed from the guard's detail (pure; the AA target shows it with NSAlert).
public struct PersistInstanceAlertText: Sendable, Equatable {
    public enum Button: String, Sendable, Equatable {
        case switchToRunning = "Switch to Running AA", openReadOnly = "Open Read-Only", quit = "Quit", takeOver = "Take Over…"
    }

    public var messageText: String
    public var informativeText: String
    /// In the order NSAlert should add them: the first is the default (Return).
    public var buttons: [Button]

    public init(messageText: String, informativeText: String, buttons: [Button]) {
        self.messageText = messageText; self.informativeText = informativeText; self.buttons = buttons
    }

    public static let folderTitle = "AA is already running with this data folder"
    public static let fileTitle = "The data file is open in another copy of AA"
    public static let choiceWithSwitch = "Switch to the copy that is already running, or open this one read-only to look without saving."
    public static let choiceWithoutSwitch = "You can open this one read-only to look without saving, or quit."

    /// `HH:mm` when `d` is today in `zone`, else `yyyy-MM-dd HH:mm`.
    public static func time(_ d: Date, now: Date, zone: TimeZone) -> String {
        let v = NetDateTime(date: d, kind: .local, zone: zone)
        let today = NetDateTime(date: now, kind: .local, zone: zone)
        return v.civilDate == today.civilDate ? v.format(.time, zone: zone) : v.format(.isoMinute, zone: zone)
    }

    /// `{holder}`: the first matching case of the DATA-172 table.
    public static func holder(_ h: PersistHolder, record: PersistLockRecord?, now: Date, zone: TimeZone) -> String {
        switch h {
        case let .sameUser(pid, started), let .sameUserNoApp(pid, started):
            guard let at = started ?? record?.acquiredUtc else { return " (process \(pid))" }
            return " (started \(time(at, now: now, zone: zone)), process \(pid))"
        case .otherUser(let user):
            return " (running for the user “\(user)” on this Mac)"
        case let .otherHostFresh(host, hb), let .otherHostStale(host, hb):
            return " on “\(host)” (last seen \(time(hb, now: now, zone: zone)))"
        case .unknown, .released, .dead:
            return ""
        }
    }

    /// The whole alert for a refused guard result.
    public static func make(_ info: PersistBlockedInfo?, now: Date, zone: TimeZone, home: String = NSHomeDirectory()) -> PersistInstanceAlertText {
        let holderCase = info?.holder ?? .unknown
        let canSwitch: Bool
        if case .sameUser = holderCase { canSwitch = true } else { canSwitch = false }
        let lease = info?.lease ?? false
        var stale = false
        var staleSince: Date?
        if case let .otherHostStale(_, hb) = holderCase { stale = true; staleSince = hb }
        let offersTakeOver: Bool
        switch holderCase {
        case .otherHostFresh, .otherHostStale: offersTakeOver = true
        case .unknown: offersTakeOver = lease
        default: offersTakeOver = false
        }
        let holderText = holder(holderCase, record: info?.record, now: now, zone: zone)
        let choice = canSwitch ? choiceWithSwitch : choiceWithoutSwitch
        let title: String
        var body: String
        switch info?.target {
        case .externalFile(let file):
            title = fileTitle
            body = "“\(file.lastPathComponent)” is being edited by another copy of AA\(holderText). Two copies would overwrite each other's changes. \(choice)"
        case .folder(let folder):
            title = folderTitle
            body = "Another copy of AA\(holderText) is using:\n\n\(abbreviate(folder.path, home: home))\n\nOnly one copy of AA can edit a data folder at a time — two copies would overwrite each other's changes. \(choice)"
        case .none:
            title = folderTitle
            body = "Another copy of AA is using this data folder.\n\nOnly one copy of AA can edit a data folder at a time — two copies would overwrite each other's changes. \(choice)"
        }
        if stale, let staleSince {
            body += "\n\nThat copy hasn't updated its claim since \(time(staleSince, now: now, zone: zone)). If that computer crashed or was switched off, you can take over."
        }
        var ordered: [Button] = []
        if canSwitch { ordered.append(.switchToRunning) }
        ordered.append(.openReadOnly)
        ordered.append(.quit)
        if offersTakeOver { ordered.append(.takeOver) }
        let def: Button = canSwitch ? .switchToRunning : (stale ? .takeOver : .openReadOnly)
        let buttons = [def] + ordered.filter { $0 != def }
        return PersistInstanceAlertText(messageText: title, informativeText: body, buttons: buttons)
    }

    /// `~/…` for paths under the home directory.
    public static func abbreviate(_ path: String, home: String) -> String {
        var h = home
        while h.count > 1, h.hasSuffix("/") { h.removeLast() }
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}
