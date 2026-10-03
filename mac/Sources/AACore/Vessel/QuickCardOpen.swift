// Spec: 10 VESSEL-025 (open a card's target: no target → info; folders open in the file manager; Not found / Open
//       failed), §6.2 ("NSWorkspace.shared.open(URL) … folders to Finder"), §6.9 (`NSWorkspace.open(folderURL)` opens
//       a Finder window; `activateFileViewerSelecting` is the "reveal" alternative), §9 Q4 / DECISIONS 10 Q4
//       (path-mapping table, UNC → smb://); ARCHITECTURE.md §9.4 (UNC row: offer "Connect to Server…" and retry);
//       DEVIATIONS W-PERSIST-13 (Locate… / Connect to Server… / File Links Settings… recovery).
import AppKit
import Foundation

/// What opening a quick card does first (VESSEL-025 steps 1 and 4).
public enum QuickCardOpenStep: Sendable, Equatable {
    /// Step 1: blank target → the `Quick card` information box.
    case noTarget
    /// Step 4 for an existing folder: open the folder itself in Finder (its contents, as Explorer does), not its
    /// parent with the folder selected.
    case openFolder(URL)
    /// Everything else goes through `AttachmentOpener.open` (files, web links, missing / unmapped paths).
    case attachment
}

/// The buttons of the unmapped-Windows-path alert of a quick card.
public enum QuickCardRecoveryChoice: Sendable, Equatable, CaseIterable {
    case connectToServer, locate, fileLinksSettings, cancel

    public var title: String {
        switch self {
        case .connectToServer: return "Connect to Server…"
        case .locate: return "Locate…"
        case .fileLinksSettings: return "Open File Links Settings…"
        case .cancel: return "Cancel"
        }
    }
}

@MainActor public enum QuickCardOpen {
    /// How long a "Connect to Server…" waits for Finder to mount the share before giving up (ARCH §9.4, the same
    /// 15 s as the file bank).
    public static let mountWaitSeconds = 15
    public static let mountPollMilliseconds = 500

    public static func step(_ card: QuickCard, dataStore: DataStore) -> QuickCardOpenStep {
        step(target: card.target, isLink: card.isLink, dataStore: dataStore)
    }

    public static func step(target: String, isLink: Bool, dataStore: DataStore) -> QuickCardOpenStep {
        if NetText.isBlank(target) { return .noTarget }
        if isLink { return .attachment }
        guard let url = AttachmentOpener.url(forStored: target, isLink: false, dataStore: dataStore), url.isFileURL
        else { return .attachment }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
              !NSWorkspace.shared.isFilePackage(atPath: url.path) else { return .attachment }
        return .openFolder(url)
    }

    /// True once a stored Windows path resolves on this Mac (a mapping was added, or the share is now mounted under
    /// /Volumes).
    public static func resolves(_ target: String, dataStore: DataStore) -> Bool {
        AttachmentOpener.url(forStored: target, isLink: false, dataStore: dataStore) != nil
    }

    /// VESSEL-025 `Not found:\n{path}` plus the Mac-only remedy line (DEVIATIONS Q4).
    public static func unmappedMessage(_ path: String) -> String {
        if let unc = PathMapper.uncParts(path) {
            return "Not found:\n\(path)\n\nThis is a Windows network share (\\\\\(unc.server)\\\(unc.share)). Connect to the server, locate the file on this Mac, or map the share to a folder in Settings ▸ File Links."
        }
        return "Not found:\n\(path)\n\nThis is a Windows path. Map its drive or server share to a folder on this Mac in Settings ▸ File Links."
    }

    /// The alert's buttons in order; the first is the default (Return), `Cancel` answers Esc. UNC paths lead with
    /// "Connect to Server…" (Finder mounts `smb://server/share`); drive letters cannot be mounted, so Locate… leads.
    public static func recoveryChoices(for path: String) -> [QuickCardRecoveryChoice] {
        if PathMapper.smbShareURL(forUNC: path) != nil {
            return [.connectToServer, .locate, .fileLinksSettings, .cancel]
        }
        return [.locate, .fileLinksSettings, .cancel]
    }

    /// Open-panel message of Locate….
    public static func locateMessage(_ path: String) -> String {
        let leaf = path.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").last.map(String.init) ?? path
        return "Locate “\(leaf)” on this Mac"
    }

    /// Status line after Locate… stored a mapping (W-PERSIST-6 wording).
    public static func mappedStatus(_ m: PathMapping) -> String { "Mapped \(m.windowsPrefix) to \(m.macPath) on this Mac." }

    /// Status line when the share did not appear within `mountWaitSeconds`.
    public static func mountTimeoutStatus(_ path: String) -> String {
        guard let unc = PathMapper.uncParts(path) else { return "The share is not mounted yet — open the card again once it is." }
        return "\\\\\(unc.server)\\\(unc.share) is not mounted yet — open the card again once Finder has connected."
    }

    /// Error text when Finder refuses to open an existing folder.
    public static func folderOpenFailed(_ url: URL) -> String { "Could not open \(url.path)." }
}
