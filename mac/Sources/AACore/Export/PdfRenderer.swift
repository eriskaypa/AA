// Spec: 11 §4.4 (PDF output: A4, Info /Title /Author (AA), /Link annotations with /URI actions, no outline —
//       DECISIONS 11 Q8), §6.1 (CGContext PDF, CTLineDraw, CGPDFContextSetURLForRect once per line fragment,
//       sRGB colours, kCGPDFContextTitle/Author/Creator), PDF-104 (fixed colours, appearance-independent).
import CoreGraphics
import CoreText
import Foundation

public enum PdfRenderer {
    /// Lays out and draws `doc` into PDF bytes. Pure (no AppKit, no main actor), safe off the main thread.
    public static func render(_ doc: PdfDoc, resolver: PdfFontResolver = .system) -> Data {
        let laid = PdfLayoutEngine(doc: doc, resolver: resolver).layout()
        return draw(laid, title: doc.title, author: doc.author)
    }

    /// The number of pages `doc` lays out to (tests, pagination checks).
    public static func pageCount(_ doc: PdfDoc, resolver: PdfFontResolver = .system) -> Int {
        PdfLayoutEngine(doc: doc, resolver: resolver).layout().pages.count
    }

    static func draw(_ laid: PdfLaidDocument, title: String, author: String) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: laid.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: title as CFString,
            kCGPDFContextAuthor: author as CFString,
            kCGPDFContextCreator: "AA for Mac" as CFString,
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        let h = laid.pageSize.height
        for page in laid.pages {
            ctx.beginPDFPage(nil)
            for op in page {
                switch op {
                case .fill(let r, let c):
                    ctx.setFillColor(PdfLayoutEngine.cgColor(c))
                    ctx.fill(CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
                case .stroke(let a, let b, let w, let c):
                    ctx.setStrokeColor(PdfLayoutEngine.cgColor(c))
                    ctx.setLineWidth(w)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: a.x, y: h - a.y))
                    ctx.addLine(to: CGPoint(x: b.x, y: h - b.y))
                    ctx.strokePath()
                case .line(let line, let p):
                    ctx.textMatrix = .identity
                    ctx.textPosition = CGPoint(x: p.x, y: h - p.y)
                    CTLineDraw(line, ctx)
                case .link(let r, let url):
                    ctx.setURL(url as CFURL, for: CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
                }
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
