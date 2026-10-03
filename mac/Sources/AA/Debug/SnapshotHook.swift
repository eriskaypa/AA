// Spec: 03 SHELL-192 (--snapshot, DEBUG only), ARCHITECTURE-BRIEF "Debug snapshot hook", ARCHITECTURE.md §9.6 (bypass
//       splash/login, load the data folder, apply the appearance, navigate, optional debug sheet, wait for layout idle,
//       render the TARGET scene's window found through SceneOpener — never keyWindow — to PNG, print the path, exit 0;
//       exit 1 on any failure).
#if DEBUG
import AppKit
import SwiftUI
import AACore

@MainActor
enum SnapshotHook {
    static func start() {
        guard let opts = LaunchCoordinator.shared.options.snapshot, let env = LaunchCoordinator.shared.env else {
            fail("snapshot: no options")
            return
        }
        switch opts.appearance?.lowercased() {
        case "dark": ShellAppearance.forcedForSnapshot = .dark
        case "light": ShellAppearance.forcedForSnapshot = .light
        default: break
        }
        ShellAppearance.apply(settings: env.settings)
        SnapshotRegistry.registerAll()
        NSApp.activate()
        Task { @MainActor in await run(opts, env: env) }
        // Watchdog: never hang a verification run.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            fail("snapshot: timed out")
        }
    }

    private static func run(_ opts: SnapshotOptions, env: AppEnvironment) async {
        let coordinator = LaunchCoordinator.shared
        let target = opts.target
        if target == "menu" {
            coordinator.enterMain()
            await waitFor { env.mainLoaded }
            await idle(seconds: 1.0)
            AppKitMenuBridge.shared.apply()
            write(text: AppKitMenuBridge.dump(), to: opts.out)
            return
        }
        let window: NSWindow?
        if let section = SectionID(rawValue: target) {
            coordinator.enterMain()
            await waitFor { env.mainLoaded && SceneOpener.shared.window(for: .main) != nil }
            env.navigator.selectSilently(section)
            if let id = opts.select { env.navigator.navigate(to: id) }
            window = SceneOpener.shared.window(for: .main)
        } else if let scene = SceneID(rawValue: target) {
            switch scene {
            case .splash:
                SceneOpener.shared.open(.splash)
                await waitFor { SceneOpener.shared.window(for: .splash) != nil }
                window = SceneOpener.shared.window(for: .splash)
            case .login:
                coordinator.showLogin()
                await waitFor { SceneOpener.shared.window(for: .login) != nil }
                window = SceneOpener.shared.window(for: .login)
            default:
                coordinator.enterMain()
                await waitFor { env.mainLoaded && SceneOpener.shared.window(for: .main) != nil }
                switch scene {
                case .main: break
                case .item:
                    guard let id = opts.select else { fail("snapshot: item needs --select <uuid>"); return }
                    env.open(.item(id))
                case .settings: env.open(.settings(tab: nil))
                case .due: env.open(.dueDates)
                case .switcher: env.open(.quickSwitcher)
                case .quickWork: env.open(.quickWork)
                case .search: env.open(.search)
                case .activityLog: env.open(.activityLog)
                case .unitConverter: env.open(.unitConverter)
                case .folderBuilder: env.open(.folderBuilder)
                case .dateCalculator: env.open(.dateCalculator)
                case .flashSync: env.open(.flashSync)
                case .crewTable: env.open(.crewTable)
                case .shortcuts: env.open(.shortcuts)
                case .about: env.open(.about)
                default: break
                }
                await waitFor { SceneOpener.shared.window(for: scene) != nil }
                window = SceneOpener.shared.window(for: scene)
            }
        } else {
            fail("snapshot: unknown target \(target)")
            return
        }
        guard let window else { fail("snapshot: the target window did not appear"); return }
        if let size = opts.parsedSize {
            var f = window.frame
            f.origin.y += f.height - size.height
            f.size = NSSize(width: size.width, height: size.height)
            window.setFrame(f, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        await idle(seconds: 1.0)
        if let sheetID = opts.sheet {
            guard let make = SnapshotRegistry.sheets[sheetID] else { fail("snapshot: unknown sheet \(sheetID)"); return }
            let presenter = SceneOpener.shared.dialogs(of: window) ?? env.mainDialogs
            Task { @MainActor in await presenter.presentSheet(.decision) { _ in make(env) } }
            await waitFor { window.attachedSheet != nil }
            await idle(seconds: 1.0)
        }
        if ProcessInfo.processInfo.environment["AA_SNAPSHOT_DUMP"] != nil, let root = window.contentView?.superview {
            var lines: [String] = []
            func walk(_ v: NSView, _ d: Int) {
                lines.append(String(repeating: " ", count: d) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) layer=\(v.layer != nil)")
                for sv in v.subviews where d < 40 { walk(sv, d + 1) }
            }
            walk(root, 0)
            FileHandle.standardError.write(Data(lines.joined(separator: "\n").utf8))
        }
        guard let png = render(window) else { fail("snapshot: rendering failed"); return }
        do {
            let url = URL(fileURLWithPath: opts.out)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            print(url.path)
            exit(0)
        } catch {
            fail("snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: Waiting

    /// Polls `condition` every 50 ms, up to 5 s.
    private static func waitFor(_ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// ≥ 2 run-loop idles plus `seconds` (layout settles).
    private static func idle(seconds: Double) async {
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    // MARK: Rendering

    /// The window's frame view (title bar and toolbar included where AppKit can cache them), with an attached sheet
    /// composited on top (centred under the title bar, as macOS shows it).
    static func render(_ window: NSWindow) -> Data? {
        guard let base = image(of: window) else { return nil }
        guard let sheet = window.attachedSheet, let sheetImage = image(of: sheet) else { return pngData(base) }
        let size = base.size
        let composite = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.black.withAlphaComponent(0.12).setFill()
            rect.fill(using: .sourceAtop)
            let s = sheetImage.size
            let titleBar = window.frame.height - window.contentLayoutRect.height
            let origin = NSPoint(x: (size.width - s.width) / 2, y: max(0, size.height - titleBar - s.height - 2))
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 18
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSBezierPath(roundedRect: NSRect(origin: origin, size: s), xRadius: 12, yRadius: 12).addClip()
            sheetImage.draw(in: NSRect(origin: origin, size: s))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return pngData(composite)
    }

    private static func image(of window: NSWindow) -> NSImage? {
        guard let content = window.contentView else { return nil }
        let view = content.superview ?? content
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // Layer rendering captures layer-backed SwiftUI / AppKit content (lists, toolbars) that `cacheDisplay` skips;
        // `cacheDisplay` is the fallback for views without a layer.
        if ProcessInfo.processInfo.environment["AA_SNAPSHOT_CACHE_DISPLAY"] == nil, let layer = view.layer {
            let scale = window.backingScaleFactor
            let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            if !layer.isGeometryFlipped == false || view.isFlipped {
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            (window.backgroundColor ?? .windowBackgroundColor).setFill()
            ctx.setFillColor((window.backgroundColor ?? .windowBackgroundColor).cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            layer.render(in: ctx)
            // macOS 26 floating sidebars / inspectors are glass portals that layer rendering leaves blank: draw each
            // narrower split-view item again with `cacheDisplay`, on a sidebar-like fill (materials are approximated).
            for item in splitItems(in: view) {
                let r = item.convert(item.bounds, to: view)
                guard r.width > 20, r.width < bounds.width - 40 else { continue }
                let fill = NSColor(name: nil) { a in
                    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                        : NSColor(srgbRed: 0.945, green: 0.945, blue: 0.95, alpha: 1)
                }
                var resolved = fill.cgColor
                window.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = fill.cgColor }
                ctx.saveGState()
                ctx.setFillColor(resolved)
                let card = flip(r, in: bounds, view).insetBy(dx: 7, dy: 7)
                ctx.addPath(CGPath(roundedRect: card, cornerWidth: 16, cornerHeight: 16, transform: nil))
                ctx.fillPath()
                ctx.restoreGState()
                // Draw every leaf-ish piece (row backgrounds, cells, headers) with cacheDisplay at its place.
                for piece in drawablePieces(in: item) {
                    let pr = piece.convert(piece.bounds, to: view)
                    if piece is NSVisualEffectView {                     // row selection: approximate the material
                        ctx.saveGState()
                        var sel = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
                        window.effectiveAppearance.performAsCurrentDrawingAppearance {
                            sel = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
                        }
                        ctx.setFillColor(sel)
                        ctx.addPath(CGPath(roundedRect: flip(pr, in: bounds, view), cornerWidth: 8, cornerHeight: 8, transform: nil))
                        ctx.fillPath()
                        ctx.restoreGState()
                        continue
                    }
                    guard pr.width > 0, pr.height > 0, let rep = piece.bitmapImageRepForCachingDisplay(in: piece.bounds)
                    else { continue }
                    piece.cacheDisplay(in: piece.bounds, to: rep)
                    if let cgp = rep.cgImage { ctx.draw(cgp, in: flip(pr, in: bounds, view)) }
                }
            }
            guard let cg = ctx.makeImage() else { return nil }
            return NSImage(cgImage: cg, size: bounds.size)
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    /// Renders a view's own layer tree (used for glass-hosted columns).
    private static func layerImage(_ v: NSView, scale: CGFloat) -> CGImage? {
        guard let layer = v.layer else { return nil }
        let b = v.bounds
        guard let ctx = CGContext(data: nil, width: Int(b.width * scale), height: Int(b.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        if v.isFlipped {
            ctx.translateBy(x: 0, y: b.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    private static func flip(_ r: NSRect, in bounds: NSRect, _ view: NSView) -> CGRect {
        view.isFlipped ? CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height) : r
    }

    /// Selected-row highlights, cells and headers of the lists inside a column.
    private static func drawablePieces(in root: NSView) -> [NSView] {
        var out: [NSView] = []
        func walk(_ v: NSView) {
            guard !v.isHidden else { return }
            let name = String(describing: type(of: v))
            if name.contains("CellView") || name.contains("HeaderView") || name == "NSVisualEffectView" && v.frame.height < 60
                || (name.hasPrefix("NSHostingView") && !name.contains("ColumnView")) {
                out.append(v)
                if name == "NSVisualEffectView" { return }
                return
            }
            for s in v.subviews { walk(s) }
        }
        walk(root)
        return out
    }

    /// The window's own split-view item wrappers (the `NavigationSplitView` sidebar / content / inspector columns).
    /// A section's internal split views (`HSplitView`, nested `NavigationSplitView`s) are NOT collected — the walk
    /// stops at the first wrapper on each path — and invisible subtrees (hidden, alpha 0, e.g. section roots kept
    /// alive at opacity 0 by `SectionContentHost`) are skipped (REQ-W-CREW-02, REQ-W-PLAN-03, REQ-W-SIRE-02).
    private static func splitItems(in root: NSView) -> [NSView] {
        var out: [NSView] = []
        func walk(_ v: NSView) {
            if v.isHidden || v.alphaValue == 0 || (v.layer.map { $0.opacity == 0 } ?? false) { return }
            if String(describing: type(of: v)).contains("SplitViewItemViewWrapper") {
                out.append(v)
                return
            }
            for s in v.subviews { walk(s) }
        }
        walk(root)
        return out
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(text: String, to path: String) {
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            print(path)
            exit(0)
        } catch {
            fail("snapshot: \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
#endif
