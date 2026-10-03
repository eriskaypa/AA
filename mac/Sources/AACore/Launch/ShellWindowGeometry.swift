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

    /// Keeps the window on a visible screen: if the frame's title-bar strip does not intersect any visible frame, it is
    /// moved into the visible frame it overlaps most (or the first one) and shrunk to fit.
    public static func clamp(_ f: ShellRect, into screens: [ShellRect]) -> ShellRect {
        guard !screens.isEmpty else { return f }
        func overlap(_ a: ShellRect, _ b: ShellRect) -> Double {
            let w = min(a.maxX, b.maxX) - max(a.x, b.x)
            let h = min(a.maxY, b.maxY) - max(a.y, b.y)
            return w > 0 && h > 0 ? w * h : 0
        }
        let titleStrip = ShellRect(x: f.x, y: f.maxY - 28, width: f.width, height: 28)
        if screens.contains(where: { overlap(titleStrip, $0) >= min(titleStrip.width, 80) * 10 }) { return f }
        let target = screens.max(by: { overlap(f, $0) < overlap(f, $1) }).flatMap { overlap(f, $0) > 0 ? $0 : nil }
            ?? screens[0]
        let w = min(f.width, target.width), h = min(f.height, target.height)
        let x = min(max(f.x, target.x), target.maxX - w)
        let y = min(max(f.y, target.y), target.maxY - h)
        return ShellRect(x: x, y: y, width: w, height: h)
    }
}
