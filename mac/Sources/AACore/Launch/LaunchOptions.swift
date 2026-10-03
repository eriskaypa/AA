// Spec: 03 BD.3.1 (parseLaunchArguments), SHELL-192 (command-line surface), §9.6 (snapshot hook arguments);
//       ARCHITECTURE.md §6.9.
import Foundation

/// The parsed command line (03 BD.3.1). `snapshot` is honoured only by DEBUG builds of the app.
public struct LaunchOptions: Sendable, Equatable {
    public var dataDir: String?
    public var version = false
    public var smokeTest = false
    public var snapshot: SnapshotOptions?

    public init(dataDir: String? = nil, version: Bool = false, smokeTest: Bool = false,
                snapshot: SnapshotOptions? = nil) {
        self.dataDir = dataDir; self.version = version; self.smokeTest = smokeTest; self.snapshot = snapshot
    }
}

/// `--snapshot <target> --out <file.png> [--appearance dark|light] [--select <uuid>] [--sheet <id>] [--size WxH]`
/// (ARCHITECTURE.md §9.6).
public struct SnapshotOptions: Sendable, Equatable {
    /// A `SectionID` raw value (`TabEquipment` …) or a `SceneID` raw value (`quick-work`, `item`, `due`, …).
    public var target: String
    public var out: String
    /// "dark" | "light" (nil = the app's own appearance rules).
    public var appearance: String?
    public var select: UUID?
    public var sheet: String?
    /// "1280x820".
    public var size: String?

    public init(target: String, out: String, appearance: String? = nil, select: UUID? = nil, sheet: String? = nil,
                size: String? = nil) {
        self.target = target; self.out = out; self.appearance = appearance; self.select = select; self.sheet = sheet
        self.size = size
    }

    /// `--size 1280x820` → (1280, 820); nil when absent or malformed.
    public var parsedSize: (width: Double, height: Double)? {
        guard let size else { return nil }
        let parts = size.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w >= 100, h >= 100 else { return nil }
        return (w, h)
    }
}

/// 03 BD.3.1 — never throws, never shows UI; warnings go to the `warn` sink (stderr in the app).
public enum LaunchArguments {
    /// The release-build notice for `--snapshot` (SHELL-192).
    public static let snapshotUnavailableMessage = "--snapshot is only available in debug builds."
    public static let dataDirMissingValueWarning = "AA: --data-dir needs a folder path; ignored"

    public static func parse(_ argv: [String]) -> LaunchOptions {
        parse(argv) { line in FileHandle.standardError.write(Data((line + "\n").utf8)) }
    }

    /// Same as `parse(_:)` with an injectable warning sink (tests).
    public static func parse(_ argv: [String], warn: (String) -> Void) -> LaunchOptions {
        var opts = LaunchOptions()
        var snapTarget: String?, snapOut: String?, snapAppearance: String?, snapSelect: UUID?
        var snapSheet: String?, snapSize: String?
        var i = 1                                               // argv[0] is the executable path
        func value(at j: Int) -> String? { j < argv.count ? argv[j] : nil }
        while i < argv.count {
            let a = argv[i]
            if a == "--data-dir" {
                if let v = value(at: i + 1), !v.hasPrefix("--") {
                    opts.dataDir = v                            // the last occurrence wins
                    i += 2
                    continue
                }
                warn(dataDirMissingValueWarning)
                i += 1
                continue
            }
            if a.hasPrefix("--data-dir=") {                     // prefix length 11
                opts.dataDir = String(a.dropFirst(11))
                i += 1
                continue
            }
            switch a {
            case "--version": opts.version = true
            case "--smoke-test": opts.smokeTest = true
            case "--snapshot", "--out", "--appearance", "--select", "--sheet", "--size":
                if let v = value(at: i + 1), !v.hasPrefix("--") {
                    switch a {
                    case "--snapshot": snapTarget = v
                    case "--out": snapOut = v
                    case "--appearance": snapAppearance = v
                    case "--select": snapSelect = UUID(uuidString: v)
                    case "--sheet": snapSheet = v
                    default: snapSize = v
                    }
                    i += 1
                }
            default:
                if a.hasPrefix("-psn_") {
                    // legacy LaunchServices process serial number — ignored
                } else if a.hasPrefix("-") && !a.hasPrefix("--") {
                    // AppKit argument-domain pair "-Key value": skip its value
                    if let v = value(at: i + 1), !v.hasPrefix("-") { i += 1 }
                }
                // anything else is ignored silently
            }
            i += 1
        }
        if let t = snapTarget {
            opts.snapshot = SnapshotOptions(target: t, out: snapOut ?? "", appearance: snapAppearance,
                                            select: snapSelect, sheet: snapSheet, size: snapSize)
        }
        return opts
    }
}
