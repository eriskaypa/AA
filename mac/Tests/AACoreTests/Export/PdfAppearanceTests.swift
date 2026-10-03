// TV: 11 §7.16 #9 (dark mode: an export made while the app appearance is darkAqua produces a byte-identical DOM and
//     the same colours as light mode), PDF-104 (fixed sRGB colours, appearance-independent).
// Every export product is built — snapshot, DOM and PDF bytes — once inside the light (aqua) and once inside the
// dark (darkAqua) appearance (the current drawing appearance, and the app's appearance when an NSApplication
// exists), then compared: the DOMs must be equal, the PDF bytes equal once the creation/modification dates and the
// random trailer /ID are removed, and the pages must rasterise to identical sRGB pixels.
import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PDF appearance independence")
struct PdfAppearanceTests {
    let stamp = "2026-09-29 14:05"

    struct Product { let name: String; let doc: PdfDoc; let pdf: Data }

    /// Builds every export product from the showcase data (all item kinds, saved lists ALL / group / list, the
    /// checklist-only PDF) plus the engine demo (colours, shading, highlight, links, strike, tables).
    func products() -> [Product] {
        let show = StoreFactory.make(data: PdfTestData.showcase())
        var out: [Product] = []
        func add(_ name: String, _ doc: PdfDoc) { out.append(Product(name: name, doc: doc, pdf: PdfRenderer.render(doc))) }
        for item in show.store.allItems() {
            add("item \(item.kind.name) \(item.name)",
                PdfItemBuilder.build(PdfSnapshotBuilder.item(item, store: show.store, isGated: { _ in false }), stamp: stamp))
        }
        for p in show.store.data.procedures where !p.steps.isEmpty {
            add("checklist \(p.name)", PdfChecklistBuilder.build(PdfSnapshotBuilder.checklist(p, store: show.store)))
        }
        let scopes: [PdfExport.SavedListsScopeRequest] =
            [.all] + show.store.data.checklistTemplates.prefix(2).flatMap { [.list($0.id), .group(ofList: $0.id)] }
        for scope in scopes {
            if case .entries(let title, let entries) = PdfExport.savedListsSelection(scope, data: show.store.data) {
                for numbered in [false, true] {
                    add("saved \(scope) \(numbered)",
                        PdfSavedListsBuilder.build(title: title, entries: entries, numbered: numbered, stamp: stamp))
                }
            }
        }
        add("engine demo", PdfEngineDemo.document())
        return out
    }

    func underAppearance(_ name: NSAppearance.Name, _ body: () -> [Product]) -> [Product] {
        let appearance = NSAppearance(named: name)!
        let app = NSApp                                         // nil in the test runner unless a suite created one
        let previous = app?.appearance
        app?.appearance = appearance
        defer { app?.appearance = previous }
        var result: [Product] = []
        appearance.performAsCurrentDrawingAppearance { result = body() }
        return result
    }

    /// The PDF bytes without the time- and run-dependent parts CoreGraphics writes: the Info dictionary's
    /// `/CreationDate` / `/ModDate` and the trailer's `/ID` pair (different on every render, even in one appearance).
    /// Decoded as ISO Latin-1, which maps every byte, so nothing else is lost.
    static func normalized(_ pdf: Data) -> String {
        var s = String(data: pdf, encoding: .isoLatin1) ?? ""
        for pattern in [#"/(CreationDate|ModDate) \([^)]*\)"#, #"/ID \[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return s
    }

    /// Every page drawn on white into an sRGB RGBA8 bitmap at 1 px/pt.
    static func raster(_ pdf: Data) -> [[UInt8]] {
        guard let provider = CGDataProvider(data: pdf as CFData), let doc = CGPDFDocument(provider) else { return [] }
        return (1...max(doc.numberOfPages, 1)).compactMap { n in
            guard let page = doc.page(at: n) else { return nil }
            let box = page.getBoxRect(.mediaBox)
            let w = Int(box.width.rounded(.up)), h = Int(box.height.rounded(.up))
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ok = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.drawPDFPage(page)
                return true
            }
            return ok ? px : nil
        }
    }

    // TV: 11 §7.16 #9
    @Test func darkAppearanceExportsMatchLight() throws {
        let light = underAppearance(.aqua) { products() }
        let dark = underAppearance(.darkAqua) { products() }
        try #require(light.count == dark.count && light.count >= 8)
        for (l, d) in zip(light, dark) {
            #expect(l.name == d.name)
            #expect(l.doc == d.doc, "DOM differs in dark mode: \(l.name)")
            let ln = Self.normalized(l.pdf)
            #expect(ln.hasPrefix("%PDF") && !ln.contains("/CreationDate") && !ln.contains("/ID ["))
            #expect(ln == Self.normalized(d.pdf), "PDF bytes differ in dark mode: \(l.name)")
        }
        // Same colours: the pages rasterise to identical pixels, and the engine demo (coloured text, shading,
        // highlight) really draws colour — not just black on white — so the comparison is not vacuous.
        for name in ["engine demo", light.first { $0.name.hasPrefix("item") }?.name ?? ""] {
            let l = try #require(light.first { $0.name == name }), d = try #require(dark.first { $0.name == name })
            let lr = Self.raster(l.pdf), dr = Self.raster(d.pdf)
            #expect(!lr.isEmpty && lr == dr, "pixels differ in dark mode: \(name)")
            if name == "engine demo", let page = lr.first {
                let coloured = stride(from: 0, to: page.count, by: 4).contains { i in
                    let r = Int(page[i]), g = Int(page[i + 1]), b = Int(page[i + 2])
                    return max(r, g, b) - min(r, g, b) > 60
                }
                #expect(coloured)
                #expect(Array(page[0..<4]) == [255, 255, 255, 255])            // page corner stays white paper
            }
        }
    }
}
