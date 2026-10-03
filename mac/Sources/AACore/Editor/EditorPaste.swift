// Spec: 05 CONT-034 (paste text only: CR LF / LF become paragraph breaks, destination formatting), CONT-035 (HTML →
//       XAML), CONT-036/037 (native rich paste incl. tables), CONT-038 + DECISIONS 05 (images are not embedded: they go
//       to the file bank with an inline notice), §6.6 (pasteboard order: own XAML type, RTF/RTFD, HTML, plain text;
//       files dropped on the text go to the file bank), ARCHITECTURE.md §9.4 (drag & drop types).
import AppKit
import UniformTypeIdentifiers

/// Which pasteboard representation a paste or drop uses.
public enum EditorPasteKind: Equatable, Sendable {
    case aaXaml, fileURLs, rtfd, rtf, html, string, image
}

public enum EditorPaste {
    public static let xamlType = NSPasteboard.PasteboardType(Identifiers.utXaml)
    public static let htmlType = NSPasteboard.PasteboardType.html
    public static let rtfType = NSPasteboard.PasteboardType.rtf
    public static let rtfdType = NSPasteboard.PasteboardType.rtfd
    public static let flatRtfdType = NSPasteboard.PasteboardType("com.apple.flat-rtfd")
    public static let stringType = NSPasteboard.PasteboardType.string
    public static let fileURLType = NSPasteboard.PasteboardType.fileURL
    public static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                                                                   NSPasteboard.PasteboardType(UTType.heic.identifier)]

    /// Every type the editor reads (paste and drop).
    public static var readableTypes: [NSPasteboard.PasteboardType] {
        [xamlType, fileURLType, rtfdType, flatRtfdType, rtfType, htmlType, stringType] + imageTypes
    }

    /// §6.6 order with two Mac rules: Finder file URLs go to the file bank, and an image-only clipboard (browser
    /// "Copy Image" also carries an `<img>` HTML stub) is an image paste.
    public static func preferredKind(_ types: [NSPasteboard.PasteboardType]) -> EditorPasteKind? {
        let set = Set(types)
        if set.contains(xamlType) { return .aaXaml }
        if set.contains(fileURLType) { return .fileURLs }
        let hasImage = imageTypes.contains { set.contains($0) }
        let hasString = set.contains(stringType)
        if set.contains(rtfdType) || set.contains(flatRtfdType) { return .rtfd }
        if set.contains(rtfType) { return .rtf }
        if hasImage && !hasString { return .image }
        if set.contains(htmlType) { return .html }
        if hasString { return .string }
        if hasImage { return .image }
        return nil
    }

    /// CONT-034: CR LF and lone CR become LF (paragraph breaks); nothing else changes.
    public static func plainText(_ s: String) -> String {
        guard s.utf16.contains(0x0D) else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// A pasted image's file-bank name, e.g. `Pasted image 2026-10-02 14.05.09.png`.
    public static func pastedImageName(at date: Date, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pasted image \(f.string(from: date)).\(ext)"
    }

    /// Bytes of an image on the pasteboard as PNG (or the original JPEG/HEIC/PNG bytes) and the extension.
    public static func imageData(from pb: NSPasteboard) -> (data: Data, ext: String)? {
        if let d = pb.data(forType: .png) { return (d, "png") }
        if let d = pb.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) { return (d, "jpg") }
        if let d = pb.data(forType: NSPasteboard.PasteboardType(UTType.heic.identifier)) { return (d, "heic") }
        if let d = pb.data(forType: .tiff), let png = pngData(fromTIFF: d) { return (png, "png") }
        return nil
    }

    public static func pngData(fromTIFF d: Data) -> Data? {
        NSBitmapImageRep(data: d)?.representation(using: .png, properties: [:])
    }
}

/// An image that was pasted inside rich text and must go to the file bank instead.
public struct EditorExtractedImage {
    public var data: Data
    public var name: String
    public init(data: Data, name: String) { self.data = data; self.name = name }
}

/// Reduces foreign rich text (RTF/RTFD from Word, Pages, Excel, Safari) to what the XAML writer can store.
@MainActor public enum EditorRichSanitiser {
    /// Attributes kept from foreign rich text.
    static let kept: Set<NSAttributedString.Key> = [.font, .foregroundColor, .backgroundColor, .underlineStyle,
                                                     .strikethroughStyle, .link, .superscript, .paragraphStyle]

    /// The sanitised text and the images it contained (removed from the text).
    public static func sanitise(_ s: NSAttributedString, base: [NSAttributedString.Key: Any],
                                now: Date = Date()) -> (text: NSAttributedString, images: [EditorExtractedImage]) {
        let out = NSMutableAttributedString()
        var images: [EditorExtractedImage] = []
        let text = s.string as NSString
        let baseFont = (base[.font] as? NSFont) ?? EditorFormatting.defaultFont()
        let ink = (base[.foregroundColor] as? NSColor) ?? EditorFormatting.editorInk
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { attrs, r, _ in
            var chunk = text.substring(with: r)
            if let att = attrs[.attachment] as? NSTextAttachment {
                if let img = extract(att, index: images.count, now: now) { images.append(img) }
                chunk = chunk.replacingOccurrences(of: "\u{FFFC}", with: "")
                if chunk.isEmpty { return }
            }
            var a: [NSAttributedString.Key: Any] = [:]
            for (k, v) in attrs where kept.contains(k) { a[k] = v }
            let f = (a[.font] as? NSFont) ?? baseFont
            a[.font] = f
            a[.aaFontFamilyName] = f.familyName ?? EditorFormatting.familyToken(base) ?? "Consolas"
            if let c = a[.foregroundColor] as? NSColor {
                a[.foregroundColor] = c.usingColorSpace(.sRGB) ?? ink
            } else {
                a[.foregroundColor] = ink
            }
            if let c = a[.backgroundColor] as? NSColor {
                if let srgb = c.usingColorSpace(.sRGB), srgb.alphaComponent > 0 { a[.backgroundColor] = srgb } else {
                    a[.backgroundColor] = nil                       // K-13: transparent is no colour
                }
            }
            if let u = a[.underlineStyle] as? Int { a[.underlineStyle] = u == 0 ? nil : NSUnderlineStyle.single.rawValue }
            if let u = a[.strikethroughStyle] as? Int { a[.strikethroughStyle] = u == 0 ? nil : NSUnderlineStyle.single.rawValue }
            if let lang = base[.aaXmlLang] { a[.aaXmlLang] = lang }
            out.append(NSAttributedString(string: chunk, attributes: a))
        }
        tagListMarkers(out)
        return (out, images)
    }

    /// TextKit 1 list paragraphs carry their marker as literal `\t{marker}\t` text; mark it `.aaListMarker` so the
    /// writer never stores it as content (05 §6.4, §4.3.7 rule 6).
    public static func tagListMarkers(_ s: NSMutableAttributedString) {
        let text = s.string as NSString
        var i = 0
        while i < text.length {
            let pr = text.paragraphRange(for: NSRange(location: i, length: 0))
            defer { i = max(NSMaxRange(pr), i + 1) }
            guard let st = s.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle,
                  !st.textLists.isEmpty, pr.length > 1, text.character(at: pr.location) == 0x09 else { continue }
            let limit = min(NSMaxRange(pr), pr.location + 16)
            var j = pr.location + 1
            while j < limit, text.character(at: j) != 0x09, text.character(at: j) != 0x0A { j += 1 }
            guard j < limit, text.character(at: j) == 0x09 else { continue }
            s.addAttribute(.aaListMarker, value: true, range: NSRange(location: pr.location, length: j + 1 - pr.location))
        }
    }

    static func extract(_ att: NSTextAttachment, index: Int, now: Date) -> EditorExtractedImage? {
        if let w = att.fileWrapper, w.isRegularFile, let d = w.regularFileContents {
            let name = w.preferredFilename ?? w.filename ?? EditorPaste.pastedImageName(at: now, ext: "png")
            return EditorExtractedImage(data: d, name: name)
        }
        if let d = att.contents {
            return EditorExtractedImage(data: d, name: EditorPaste.pastedImageName(at: now.addingTimeInterval(Double(index)),
                                                                               ext: "png"))
        }
        if let img = att.image, let tiff = img.tiffRepresentation, let png = EditorPaste.pngData(fromTIFF: tiff) {
            return EditorExtractedImage(data: png, name: EditorPaste.pastedImageName(at: now.addingTimeInterval(Double(index)),
                                                                                 ext: "png"))
        }
        return nil
    }

    /// CONT-034 paste text only: the text with the destination's typing attributes (never a lock or a link).
    public static func plain(_ s: String, typing: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var a = EditorLocking.unlockedTypingAttributes(typing)
        if a[.link] != nil { a = EditorLinkRules.removingLink(a) }
        return NSAttributedString(string: EditorPaste.plainText(s), attributes: a)
    }
}
