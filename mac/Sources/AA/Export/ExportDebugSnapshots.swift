// Spec: ARCHITECTURE.md §9.6 — W-PDF's debug sheets for the snapshot hook: the list-style prompt (PDF-023,
//       CONT-049) with one and several lists, the busy sheet (PDF-005), and a preview of the first page of the
//       item PDF of the first item in the loaded data folder (the whole snapshot → DOM → layout → PDF pipeline).
import AppKit
import CoreGraphics
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_PDF() {
        register("w-pdf.list-style") { _ in
            AnyView(PdfListStyleSheet(prompt: PdfExport.listStylePrompt(entryCount: 1)) { _ in })
        }
        register("w-pdf.list-style-many") { _ in
            AnyView(PdfListStyleSheet(prompt: PdfExport.listStylePrompt(entryCount: 4)) { _ in })
        }
        register("w-pdf.busy") { _ in
            AnyView(PdfBusySheet(text: PdfExport.busyText, state: PdfBusyState(), dismiss: {}))
        }
        register("w-pdf.preview") { env in
            AnyView(PdfDebugPreview(env: env))
        }
    }
}

/// Debug-only: the first page of the item PDF of the first top-level item, drawn into an image.
private struct PdfDebugPreview: View {
    let env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            if let item = env.store.allItems().first(where: { $0.kind == .task }) ?? env.store.allItems().first {
                Text(PdfExport.itemFileName(kind: item.kind, name: item.name)).font(.headline)
                if let img = Self.firstPage(item, env: env) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 420)
                        .overlay(Rectangle().stroke(AAColor.border))
                }
            } else {
                AAEmptyState(title: "No items", symbol: "doc.richtext", message: "The data folder has no items.")
            }
        }
        .padding(AASpacing.l)
        .aaSheet(.closeType)
    }

    static func firstPage(_ item: HierarchyItem, env: AppEnvironment) -> NSImage? {
        let s = PdfSnapshotBuilder.item(item, store: env.store, isGated: env.locks.isGated)
        let data = PdfExport.itemPDF(s, stamp: PdfScaffold.stamp(env.clock.now()))
        guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 1.5
        guard let ctx = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: box.width * scale, height: box.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: box.width, height: box.height))
    }
}
