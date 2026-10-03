// Spec: 03 SHELL-032 (window geometry persistence), §6.3 (Mac conversion and restore rules), W-1 / SHELL-027
//       (selected tab restored after the order), 01 DATA-035. Vectors: 03 §7.1 "UiState restore",
//       "Coordinate conversion", "Selected tab restore".
import Foundation

/// A rectangle in AppKit screen coordinates (bottom-left origin).
public struct ShellRect: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public enum ShellWindowStateName: String, Sendable { case normal = "Normal", maximized = "Maximized", minimized = "Minimized" }

/// Pure conversion between the Mac frame and the WPF `UiState` keys.
public enum ShellWindowGeometry {
    public static let minimumRestoredSize = 200.0
    public static let defaultSize = (width: 1280.0, height: 820.0)
    /// The main window's `minSize` (`NSWindow.setFrame` does not enforce it, so the restore applies it).
    public static let macMinimumSize = (width: 860.0, height: 560.0)

    /// `WindowLeft = frame.minX`, `WindowTop = primary.maxY − frame.maxY` (WPF's top-left origin on the primary
    /// screen), `WindowWidth/Height = frame size` (outer frame).
    public static func wpfValues(frame: ShellRect, primaryScreenMaxY: Double)
        -> (left: Double, top: Double, width: Double, height: Double) {
        (frame.x, primaryScreenMaxY - frame.maxY, frame.width, frame.height)
    }

    /// The inverse of `wpfValues`.
    public static func macFrame(left: Double, top: Double, width: Double, height: Double, primaryScreenMaxY: Double) -> ShellRect {
        ShellRect(x: left, y: primaryScreenMaxY - top - height, width: width, height: height)
    }

    /// Case-sensitive `Enum.TryParse` emulation: `Normal`, `Maximized`, `Minimized`, and the numeric strings `0`, `1`,
    /// `2` (WPF `WindowState` values). `Minimized` restores as normal; anything else → normal (never crash).
    public static func restoredState(_ text: String?) -> ShellWindowStateName {
        guard let text else { return .normal }
        switch text {
        case "Maximized", "2": return .maximized
        default: return .normal
        }
    }

    /// The frame to apply at launch, or nil to keep the default. Width/height only when > 200; left/top whenever
    /// present; then clamped into the union of the visible screens (MAC-ADAPT, 03 §6.3).
    public static func restoredFrame(left: Double?, top: Double?, width: Double?, height: Double?,
                                     current: ShellRect, primaryScreenMaxY: Double, visibleFrames: [ShellRect]) -> ShellRect? {
        if left == nil, top == nil, width == nil, height == nil { return nil }
        var w = current.width, h = current.height
        if let width, width > minimumRestoredSize { w = width }
        if let height, height > minimumRestoredSize { h = height }
        // WPF top-left of the current frame, then overridden by the stored values.
        let cur = wpfValues(frame: current, primaryScreenMaxY: primaryScreenMaxY)
        let l = left ?? cur.left
        let t = top ?? cur.top
        let frame = macFrame(left: l, top: t, width: w, height: h, primaryScreenMaxY: primaryScreenMaxY)
        return clamp(frame, into: visibleFrames)
    }

    /// Keeps the window on a visible screen (03 §6.3 "clamp to the union of NSScreen.visibleFrames"):
    /// * the target screen is the one the 28-pt title strip overlaps most (the frame's best overlap, else the first);
    /// * the size is raised to `macMinimumSize` and then shrunk to fit the target's visible frame (a Windows PC's
    ///   1920×1040 bounds on a 1470×919 MacBook);
    /// * a frame whose title strip is (sufficiently) visible keeps its position unless it had to shrink — it may span
    ///   two screens; otherwise it is moved inside the target.
    public static func clamp(_ f: ShellRect, into screens: [ShellRect]) -> ShellRect {
        guard !screens.isEmpty else { return f }
        func overlap(_ a: ShellRect, _ b: ShellRect) -> Double {
            let w = min(a.maxX, b.maxX) - max(a.x, b.x)
            let h = min(a.maxY, b.maxY) - max(a.y, b.y)
            return w > 0 && h > 0 ? w * h : 0
        }
        let titleStrip = ShellRect(x: f.x, y: f.maxY - 28, width: f.width, height: 28)
        let stripVisible = screens.contains(where: { overlap(titleStrip, $0) >= min(titleStrip.width, 80) * 10 })
        let byStrip = screens.max(by: { overlap(titleStrip, $0) < overlap(titleStrip, $1) }).flatMap {
            overlap(titleStrip, $0) > 0 ? $0 : nil
        }
        let byFrame = screens.max(by: { overlap(f, $0) < overlap(f, $1) }).flatMap { overlap(f, $0) > 0 ? $0 : nil }
        let target = (stripVisible ? byStrip : nil) ?? byFrame ?? screens[0]
        let w = min(max(f.width, macMinimumSize.width), target.width)
        let h = min(max(f.height, macMinimumSize.height), target.height)
        if stripVisible, w == f.width, h == f.height { return f }
        // Keep the top-left corner where it was (WPF anchors Left/Top), then pull the frame inside the target.
        let top = f.maxY
        let x = min(max(f.x, target.x), target.maxX - w)
        let y = min(max(top - h, target.y), target.maxY - h)
        return ShellRect(x: x, y: y, width: w, height: h)
    }
}
