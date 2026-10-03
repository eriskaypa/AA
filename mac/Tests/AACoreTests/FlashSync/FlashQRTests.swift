// TV: 13 §7.9 — QR generation (alphanumeric mode, v22-L/105 modules for a data frame, boosted ECC for manifests),
//     golden module matrices from Nayuki's reference implementation (qrcodegen 1.8.0, Fixtures/flashsync/qr-golden.json),
//     the independent CIQRCodeDescriptor + CIBarcodeGenerator cross-check, the synthetic optical loop through Apple
//     Vision (incl. the all-zero tail frame and a mask-0 symbol) and degradations (1.5 px/module, blur, perspective);
//     FLASH-071, FLASH-016.
import CoreImage
import Foundation
import Testing
import Vision
@testable import AACore

@Suite struct FlashQRTests {
    struct Golden {
        let name: String, text: String, ecl: FlashQREcc, forcedMask: Int
        let version: Int, eccOut: FlashQREcc, mask: Int, size: Int, rows: [String]
    }

    static let goldens: [Golden] = {
        guard let d = try? Fixtures.data("flashsync/qr-golden.json"), case .object(let root)? = try? JSONParser.parse(d) else { return [] }
        func ecc(_ s: String?) -> FlashQREcc { ["L": .low, "M": .medium, "Q": .quartile, "H": .high][s ?? "L"] ?? .low }
        return (root["cases"]?.arrayValue ?? []).compactMap { v in
            guard let o = v.objectValue else { return nil }
            return Golden(name: o["name"]!.stringValue!, text: o["text"]!.stringValue!, ecl: ecc(o["ecl"]?.stringValue),
                          forcedMask: FlashTestKit.int(o["forcedMask"]), version: FlashTestKit.int(o["version"]),
                          eccOut: ecc(o["eccOut"]?.stringValue), mask: FlashTestKit.int(o["mask"]),
                          size: FlashTestKit.int(o["size"]), rows: (o["rows"]?.arrayValue ?? []).compactMap(\.stringValue))
        }
    }()

    static func encode(_ g: Golden) throws -> FlashQRCode {
        try FlashQRCode.encodeSegments(FlashQRSegment.makeSegments(g.text), ecl: g.ecl, mask: g.forcedMask)
    }

    // TV: 13 §7.9 golden matrices (SHOULD: bit-identical to Nayuki encode_text)
    @Test func goldenMatricesAreBitIdentical() throws {
        #expect(Self.goldens.count == 20)
        for g in Self.goldens {
            let qr = try Self.encode(g)
            #expect(qr.version == g.version && qr.errorCorrectionLevel == g.eccOut && qr.mask == g.mask && qr.size == g.size,
                    "\(g.name): v\(qr.version) \(qr.errorCorrectionLevel) mask \(qr.mask)")
            let rows = (0 ..< qr.size).map { y in String((0 ..< qr.size).map { qr.module($0, y) ? "1" : "0" }) }
            #expect(rows == g.rows, "\(g.name)")
        }
    }

    // TV: 13 §3.10 table — symbol sizes for the frames Flash Sync shows
    @Test func symbolSizesMatchTheSpecTable() throws {
        let data = FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 7, seed: 9,
                                                                           payload: FlashTestKit.noise(900, seed: 1))))
        let d = try FlashQRCode.encodeText(data, ecl: .low)
        #expect(d.version == 22 && d.errorCorrectionLevel == .low && d.size == 105)
        #expect(FlashQRSegment.makeSegments(data).first?.mode == .alphanumeric)
        func manifest(_ label: String) -> String {
            FlashBase45.encode(FlashFrame.encodeManifest(FlashManifestFrame(session: 1, codedBytes: 1, rawBytes: 1, chunkSize: 900,
                                                                             chunkCount: 1, crc32: 1, kind: .fullSnapshot, label: label)))
        }
        let full = try FlashQRCode.encodeText(manifest("full database"), ecl: .low)
        #expect(full.version == 3 && full.errorCorrectionLevel == .medium && full.size == 29)
        let empty = try FlashQRCode.encodeText(manifest(""), ecl: .low)
        #expect(empty.version == 2 && empty.errorCorrectionLevel == .medium)
        let long = try FlashQRCode.encodeText(manifest(String(repeating: "x", count: 200)), ecl: .low)
        #expect(long.version == 7 && long.errorCorrectionLevel == .low && long.size == 45)
        // Forced byte mode would push the data frame to v26 (121 modules) — what CoreImage's generator would do.
        let bytes = try FlashQRCode.encodeSegments([FlashQRSegment.makeBytes(Array(data.utf8))], ecl: .low)
        #expect(bytes.version == 26 && bytes.size == 121)
    }

    @Test func capacityAndReedSolomonBasics() throws {
        #expect(FlashQRCode.numRawDataModules(1) == 208)
        #expect(FlashQRCode.numRawDataModules(40) == 29648)
        #expect(FlashQRCode.numDataCodewords(1, .low) == 19)
        #expect(FlashQRCode.numDataCodewords(22, .low) == 1006)
        #expect(FlashQRCode.numDataCodewords(40, .high) == 1276)
        #expect(FlashQRCode.reedSolomonMultiply(0x80, 0x02) == 0x1D)
        #expect(FlashQRCode.reedSolomonDivisor(degree: 1) == [1])
        // The zero-prefixed block: ECC of an all-zero block is all zero, but a block whose data merely STARTS with
        // ≥ eccPerBlock zero codewords followed by non-zero data must not be (the QRCoder bug).
        let div = FlashQRCode.reedSolomonDivisor(degree: 28)
        #expect(FlashQRCode.reedSolomonRemainder([UInt8](repeating: 0, count: 100), divisor: div).allSatisfy { $0 == 0 })
        let tail = [UInt8](repeating: 0, count: 90) + [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        #expect(!FlashQRCode.reedSolomonRemainder(tail, divisor: div).allSatisfy { $0 == 0 })
        #expect(throws: FlashQRError.self) {
            _ = try FlashQRCode.encodeText(String(repeating: "A", count: 4300), ecl: .low)
        }
    }

    // MARK: Independent cross-check through CoreImage (13 §7.9)

    /// Renders a payload + version + mask through CIQRCodeDescriptor/CIBarcodeGenerator; returns the module grid
    /// (the generator draws one pixel per module with its own 1-module margin).
    static func coreImageModules(payload: [UInt8], _ qr: FlashQRCode) -> [Bool]? {
        let level: CIQRCodeDescriptor.ErrorCorrectionLevel
        switch qr.errorCorrectionLevel {
        case .low: level = .levelL
        case .medium: level = .levelM
        case .quartile: level = .levelQ
        case .high: level = .levelH
        }
        guard let desc = CIQRCodeDescriptor(payload: Data(payload), symbolVersion: qr.version,
                                            maskPattern: UInt8(qr.mask), errorCorrectionLevel: level),
              let filter = CIFilter(name: "CIBarcodeGenerator") else { return nil }
        filter.setValue(desc, forKey: "inputBarcodeDescriptor")
        guard let image = filter.outputImage else { return nil }
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let w = Int(image.extent.width), h = Int(image.extent.height)
        guard w == h, w >= qr.size, (w - qr.size) % 2 == 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &px, rowBytes: w * 4, bounds: image.extent, format: .RGBA8,
                   colorSpace: CGColorSpaceCreateDeviceRGB())
        let margin = (w - qr.size) / 2
        return (0 ..< qr.size).flatMap { y in (0 ..< qr.size).map { x in px[((y + margin) * w + x + margin) * 4] < 128 } }
    }

    // Our ECC + interleaving-independent placement, format and version bits must equal CoreImage's: once with our
    // data+ECC codewords (block order), once with data only (CoreImage computes the ECC itself).
    @Test func coreImageDescriptorCrossCheck() throws {
        var compared = 0
        for g in Self.goldens {
            let qr = try Self.encode(g)
            guard let withEcc = Self.coreImageModules(payload: qr.dataThenEccCodewords, qr),
                  let dataOnly = Self.coreImageModules(payload: qr.dataCodewords, qr) else { continue }
            #expect(withEcc == qr.modules, "\(g.name) differs from CoreImage (our ECC)")
            #expect(dataOnly == qr.modules, "\(g.name) differs from CoreImage (CoreImage ECC)")
            compared += 1
        }
        #expect(compared == Self.goldens.count, "CIQRCodeDescriptor must accept every golden symbol")
    }

    // MARK: Optical loop through Vision (13 §7.9)

    /// The receiver's detector (current + legacy Vision revision, CIDetector fallback).
    static func detect(_ image: CGImage) -> [String] { FlashQRDetector().detect(cgImage: image) }

    /// Vision's current revision alone — what an Apple reader (e.g. the iPhone) does by default.
    static func currentVisionOnly(_ image: CGImage) -> [String] {
        FlashQRDetector(useLegacyRevision: false, useCoreImageFallback: false).detect(cgImage: image)
    }

    static func ciImage(_ cg: CGImage) -> CIImage { CIImage(cgImage: cg) }

    static func cg(_ ci: CIImage) -> CGImage? { CIContext().createCGImage(ci, from: ci.extent) }

    @Test func goldenSymbolsDecodeThroughVision() throws {
        for g in Self.goldens {
            let qr = try Self.encode(g)
            let image = try #require(FlashQRRaster.cgImage(qr, scale: 4))
            #expect(Self.detect(image) == [g.text], "\(g.name) (v\(qr.version) mask \(qr.mask)) must read back exactly")
        }
    }

    // TV: 13 §7.9 synthetic optical loop — every frame of a real change set and of a K≈30 payload, rendered at
    // 3 px/module with the quiet zone, detected by Vision, reassembled byte-identically.
    @Test func syntheticOpticalLoop() throws {
        let change = Array(#"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","Sets":{"Equipment":[{"Id":"8a3d6f3e-1b2c-4d5e-8f90-123456789abc","Name":"Cargo compressor No. 1","RichTextXaml":"<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph>Overhaul due</Paragraph></Section>"}]}}"#.utf8)
        let big = FlashTestKit.sampleJSON(approxBytes: 50_000, seed: 21)
        for (payload, kind) in [(change, FlashFrameKind.changeSet), (big, .fullSnapshot)] {
            let enc = try FlashEncoder(payload: payload, kind: kind, label: "optical", session: 0x5151)
            let dec = FlashDecoder()
            var frames = 0
            while !dec.isComplete && frames < enc.chunkCount * 3 + 24 {
                let text = enc.next()
                frames += 1
                let qr = try FlashQRCode.flashFrame(text)
                let image = try #require(FlashQRRaster.cgImage(qr, scale: 3))
                for s in Self.detect(image) { dec.ingest(s) }
            }
            #expect(dec.finish() == payload, "K=\(enc.chunkCount)")
        }
        // The all-zero tail frame: Nayuki picks mask 0 (what Windows flashes) — the receiver still reads it.
        let zero = FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 0x1234, seed: 0,
                                                                           payload: [UInt8](repeating: 0, count: 900))))
        let zq = try FlashQRCode.encodeText(zero, ecl: .low)
        #expect(zq.mask == 0)
        #expect(Self.detect(try #require(FlashQRRaster.cgImage(zq, scale: 3))) == [zero])
    }

    // DEV-FLASH-05: zero-heavy tail frames flashed by the Mac use a mask Apple's CURRENT reader decodes on its own,
    // and the receiver's combined detector reads every mask Windows (Nayuki) may choose.
    @Test func zeroHeavyFramesAndMaskPolicy() throws {
        var nayukiUnreadableByCurrentVision = 0
        for dataLen in [0, 1, 10, 40, 90] {
            var payload = FlashTestKit.noise(dataLen, seed: UInt64(dataLen))
            payload += [UInt8](repeating: 0, count: 900 - dataLen)
            let text = FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 0x2222, seed: 3, payload: payload)))
            let ours = try FlashQRCode.flashFrame(text)
            #expect(FlashQRCode.appleReaderSafeMasks.contains(ours.mask))
            #expect(Self.currentVisionOnly(try #require(FlashQRRaster.cgImage(ours, scale: 4))) == [text], "tail \(dataLen)")
            for mask in 0 ..< 8 {
                let windows = try FlashQRCode.encodeSegments(FlashQRSegment.makeSegments(text), ecl: .low, mask: mask)
                let img = try #require(FlashQRRaster.cgImage(windows, scale: 4))
                #expect(Self.detect(img) == [text], "tail \(dataLen) mask \(mask)")
                if mask == (try FlashQRCode.encodeText(text, ecl: .low)).mask, Self.currentVisionOnly(img) != [text] {
                    nayukiUnreadableByCurrentVision += 1
                }
            }
        }
        print("Flash Sync: \(nayukiUnreadableByCurrentVision)/5 Nayuki-masked zero-heavy frames unreadable by current Vision alone")
    }

    // TV: 13 §7.9 degradations — report the success rate; zero wrong payloads allowed
    @Test func degradations() throws {
        let enc = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 20_000, seed: 5), kind: .changeSet,
                                   label: "degraded", session: 77)
        var texts: [String] = []
        for _ in 0 ..< 12 { texts.append(enc.next()) }
        var ok = 0, wrong = 0, total = 0
        for text in texts {
            let qr = try FlashQRCode.flashFrame(text)
            let base = Self.ciImage(try #require(FlashQRRaster.cgImage(qr, scale: 6)))
            let small = base.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))       // 1.5 px/module
            let blur = base.applyingGaussianBlur(sigma: 1.2).cropped(to: base.extent)
            let w = base.extent.width, h = base.extent.height
            let warp = base.applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": CIVector(x: w * 0.06, y: h * 0.97), "inputTopRight": CIVector(x: w * 0.95, y: h),
                "inputBottomLeft": CIVector(x: 0, y: 0), "inputBottomRight": CIVector(x: w * 0.9, y: h * 0.05)])
            for variant in [small, blur, warp] {
                guard let img = Self.cg(variant.composited(over: CIImage(color: .white).cropped(to: variant.extent))) else { continue }
                total += 1
                let found = Self.detect(img)
                if found.contains(text) { ok += 1 }
                wrong += found.filter { $0 != text }.count
            }
        }
        print("Flash Sync degradations: \(ok)/\(total) decoded, \(wrong) wrong")
        #expect(wrong == 0)
        #expect(ok > 0)
    }
}
