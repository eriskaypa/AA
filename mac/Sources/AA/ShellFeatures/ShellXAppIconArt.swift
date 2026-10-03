// Spec: 03 Appendix C "App icon art" (outer ring #1B1B1B, ring #313131, face #4F4F4F, highlight ring #626262, a bold
//       sans "A" in lime #87D639, transparent corners), SHELL-184 (AppIcon), SHELL-199 (unbundled runs have no bundle
//       icon). The same geometry is drawn at 1024 px by `Packaging/make-app-icon.swift` for `Resources/AppIcon-1024.png`.
import AppKit
import SwiftUI
import AACore

/// AA's round "A" disc as vector art; used where the bundle icon is unavailable (`swift run`).
struct ShellXAppIconArt: View {
    var size: CGFloat = 112

    /// Fractions of the icon size (diameters), matching the 256-px ICO frame.
    private enum Geometry {
        static let outer: CGFloat = 0.90, ring: CGFloat = 0.80, highlight: CGFloat = 0.66, face: CGFloat = 0.62
        static let letter: CGFloat = 0.46
    }

    /// The icon palette (brand art, not UI tokens).
    private enum Palette {
        static let outer = Color(nsColor: AAColor.hex("#1B1B1B"))
        static let ring = Color(nsColor: AAColor.hex("#313131"))
        static let highlight = Color(nsColor: AAColor.hex("#626262"))
        static let face = Color(nsColor: AAColor.hex("#4F4F4F"))
        static let letter = Color(nsColor: AAColor.hex("#87D639"))
    }

    var body: some View {
        ZStack {
            Circle().fill(Palette.outer).frame(width: size * Geometry.outer, height: size * Geometry.outer)
            Circle().fill(Palette.ring).frame(width: size * Geometry.ring, height: size * Geometry.ring)
            Circle().fill(Palette.highlight).frame(width: size * Geometry.highlight, height: size * Geometry.highlight)
            Circle().fill(Palette.face).frame(width: size * Geometry.face, height: size * Geometry.face)
            Text("A")
                .font(.system(size: size * Geometry.letter, weight: .heavy, design: .default))
                .foregroundStyle(Palette.letter)
                .offset(y: -size * 0.01)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: size * 0.05, y: size * 0.02)
        .accessibilityHidden(true)
    }
}

/// The app icon: the bundle's icon when AA runs as an app, the vector art otherwise.
struct ShellXAppIcon: View {
    var size: CGFloat = 112

    var body: some View {
        if ShellLaunchEnvironment.isCurrentProcessUnbundled {
            ShellXAppIconArt(size: size)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
