import Foundation
import Testing
import Tessera
import UIKit
@testable import TesseraUI

/// TES-372: the saved-image reader with Apple's real text recognizer (Vision), on the iOS the test runs on.
///
/// Every other test of the reading path feeds text in. This one draws the project's own TD3 specimen
/// ("UTO" = fictional Utopia, synthetic, not real document data) into a picture at run time, saves it as a
/// PNG and reads it the way an app does (`SavedImageMrzReader` + `visionSavedImageRecognizer`). No image
/// file is kept in the repository.
///
/// What fails the test: an OCR failure, no text read at all, or text that does not hold the specimen's
/// name. Whether the whole MRZ decodes depends on how Vision reads a run of `<` in a system font, so the
/// outcome is printed (`old-ios-ocr:` line, no document values) but not required. The workflow
/// `.github/workflows/old-ios.yml` runs this on each old iOS version.
@MainActor
struct SavedImageVisionReadTests {
    private static let specimenLines = [
        "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<",
        "T220001293UTO9003152F3403141S98765432<<<<<20",
    ]

    @Test func visionReadsTheSpecimenPicture() async throws {
        let url = try Self.writeSpecimenPicture()
        defer { try? FileManager.default.removeItem(at: url) }

        let acknowledgement = SavedImageReadingAcknowledgement()
        let reader = SavedImageMrzReader<NSURL>(
            acknowledgement: acknowledgement,
            recognizer: VisionSavedImageRecognizerKt.visionSavedImageRecognizer(acknowledgement: acknowledgement),
            mode: ParsingMode.lenient,
            tolerant: false,
            metadataReader: nil,
            metadataPolicy: CaptureMetadataPolicy.none,
            telemetry: NoOpTelemetrySink(),
            referenceTimeProvider: { @Sendable in nowInstant() }
        )
        // The same bridge ScannerModel uses: the K/N result arrives on another thread, moved here once.
        let boxed: Transferred<SavedImageScanResult?> = await withCheckedContinuation { continuation in
            reader.read(image: url as NSURL) { scanResult, _ in
                continuation.resume(returning: Transferred(scanResult))
            }
        }
        reader.close()
        let result = try #require(boxed.value, "The reader gave no result")

        let lines: [String]
        let outcome: String
        switch result.scan {
        case let decoded as MrzScanResultDecoded:
            lines = decoded.recognizedText.lines.map(\.text)
            outcome = decoded.parse is ParseResult.Failure ? "decoded, parse failed" : "decoded"
        case let none as MrzScanResultNoMrzFound:
            lines = none.recognizedText.lines.map(\.text)
            outcome = "no MRZ found"
        case let failed as MrzScanResultCaptureError:
            Issue.record("Vision failed on iOS \(ProcessInfo.processInfo.operatingSystemVersionString): \(failed.error)")
            return
        default:
            Issue.record("Unknown scan result: \(type(of: result.scan))")
            return
        }
        // Counts and outcome only, never the text.
        print("old-ios-ocr: iOS \(ProcessInfo.processInfo.operatingSystemVersionString): \(outcome), \(lines.count) lines")

        #expect(!lines.isEmpty, "Vision read no text from the specimen picture")
        let joined = lines.joined().filter { !$0.isWhitespace }
        #expect(joined.contains("SPECIMEN"), "Vision's text does not hold the specimen's name")
    }

    /// Draws the two specimen lines, black on white, large and with margins, and saves them as a PNG.
    private static func writeSpecimenPicture() throws -> URL {
        let font = UIFont(name: "Courier-Bold", size: 44) ?? UIFont.monospacedSystemFont(ofSize: 44, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let sizes = specimenLines.map { ($0 as NSString).size(withAttributes: attributes) }
        let margin: CGFloat = 80
        let lineGap: CGFloat = 24
        let width = (sizes.map(\.width).max() ?? 0) + 2 * margin
        let height = sizes.map(\.height).reduce(0, +) + lineGap + 2 * margin

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var y = margin
            for (line, size) in zip(specimenLines, sizes) {
                (line as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
                y += size.height + lineGap
            }
        }
        let data = try #require(image.pngData(), "Could not encode the specimen picture")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-specimen-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}

/// Moves a non-Sendable value across one hop, owned by one side at a time.
private struct Transferred<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
