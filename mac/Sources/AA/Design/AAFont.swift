// Spec: 03 §6.6.4 (Consolas → SF Mono → Menlo; sizes), SHELL-154; ARCHITECTURE.md §8.3.
import AppKit
import SwiftUI

/// The app's monospaced identity (Consolas when installed, otherwise SF Mono, else Menlo).
enum AAFont {
    static var isConsolasInstalled: Bool { consolasInstalled }

    private static let consolasInstalled: Bool = NSFont(name: "Consolas", size: 13) != nil

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if consolasInstalled {
            let base = NSFont(name: weight >= .semibold ? "Consolas-Bold" : "Consolas", size: size)
                ?? NSFont(name: "Consolas", size: size)
            if let base { return base }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Font {
    /// SwiftUI form of `AAFont.mono` (the root font of every app-drawn surface).
    static func aaMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if AAFont.isConsolasInstalled {
            return Font.custom("Consolas", fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Type scale (03 §6.6.4).
enum AAType {
    static let body: CGFloat = 13, small: CGFloat = 12, caption: CGFloat = 11, strip: CGFloat = 11,
               title: CGFloat = 16, brand: CGFloat = 22, loginBrand: CGFloat = 28, editor: CGFloat = 14
}

/// Spacing and radii (§8.4).
enum AASpacing {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
}

enum AARadius {
    static let control: CGFloat = 4, boardCard: CGFloat = 6, tile: CGFloat = 8, quickCard: CGFloat = 10,
               floatingPanel: CGFloat = 12, sidebarTile: CGFloat = 5
}
