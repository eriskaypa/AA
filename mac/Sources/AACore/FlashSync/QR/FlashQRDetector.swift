// Spec: 13 §6.4 step 5 / FLASH-037 (per-frame detection returning EVERY QR string visible, fed untrimmed to the
//       decoder), §3.13 (replaces the Windows OpenCV WeChat detector), §7.9 (optical loop).
// Measured on this toolchain (FlashQRTests): Vision's current barcode revisions (3–4) miss perfectly clean symbols whose
// data is mostly zero bytes under masks 0/1/2/3/5 — exactly the zero-padded tail chunk a Windows sender (Nayuki, same
// masks) flashes. Vision revision 2 and CoreImage's CIDetector read them all. So every frame runs the current and the
// legacy Vision revision together, and CIDetector only when both found nothing (Deviations/W-FLASH.md DEV-FLASH-05).
import CoreImage
import CoreVideo
import Foundation
import Vision

/// QR reader for camera frames and test images. Confine one instance to one queue (the capture queue).
public final class FlashQRDetector: @unchecked Sendable {
    /// The legacy Vision revision that reads zero-heavy symbols (used only when the OS still offers it).
    public static let legacyRevision = 2

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private lazy var ciDetector: CIDetector? = CIDetector(ofType: CIDetectorTypeQRCode, context: ciContext,
                                                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    public private(set) var usesLegacyRevision: Bool

    public init(useLegacyRevision: Bool = true, useCoreImageFallback: Bool = true) {
        usesLegacyRevision = useLegacyRevision
            && VNDetectBarcodesRequest.supportedRevisions.contains(FlashQRDetector.legacyRevision)
        self.useCoreImageFallback = useCoreImageFallback
    }

    private let useCoreImageFallback: Bool

    private func requests() -> [VNDetectBarcodesRequest] {
        let current = VNDetectBarcodesRequest()
        current.symbologies = [.qr]
        guard usesLegacyRevision else { return [current] }
        let legacy = VNDetectBarcodesRequest()
        legacy.revision = FlashQRDetector.legacyRevision
        legacy.symbologies = [.qr]
        return [current, legacy]
    }

    /// Every distinct QR payload string in a camera frame (order of first detection; never trimmed).
    public func detect(pixelBuffer: CVPixelBuffer) -> [String] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        var found = run(handler)
        if found.isEmpty, useCoreImageFallback { found = coreImage(CIImage(cvPixelBuffer: pixelBuffer)) }
        return found
    }

    /// The same for a still image.
    public func detect(cgImage: CGImage) -> [String] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        var found = run(handler)
        if found.isEmpty, useCoreImageFallback { found = coreImage(CIImage(cgImage: cgImage)) }
        return found
    }

    private func run(_ handler: VNImageRequestHandler) -> [String] {
        let reqs = requests()
        do { try handler.perform(reqs) } catch { return [] }
        var out: [String] = []
        for r in reqs {
            for obs in r.results ?? [] {
                if let s = obs.payloadStringValue, !out.contains(s) { out.append(s) }
            }
        }
        return out
    }

    private func coreImage(_ image: CIImage) -> [String] {
        guard let det = ciDetector else { return [] }
        var out: [String] = []
        for f in det.features(in: image) {
            if let s = (f as? CIQRCodeFeature)?.messageString, !out.contains(s) { out.append(s) }
        }
        return out
    }
}
