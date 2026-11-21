// Sample for TES-A-116 "Read an MRZ from a saved image on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-116 block 1: Package.swift dependency lines

// region TES-A-116 block 2
import Foundation
import Tessera

func nowInstant() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(
        epochMilliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded())
    )
}
// endregion

// region TES-A-116 block 3
func makeSavedImageReader() -> SavedImageMrzReader<NSURL> {
    let acknowledgement = SavedImageReadingAcknowledgement()
    return SavedImageMrzReader<NSURL>(
        acknowledgement: acknowledgement,
        recognizer: VisionSavedImageRecognizerKt.visionSavedImageRecognizer(acknowledgement: acknowledgement),
        mode: ParsingMode.lenient,
        tolerant: false,
        metadataReader: nil,
        metadataPolicy: CaptureMetadataPolicy.none,
        telemetry: NoOpTelemetrySink(),
        referenceTimeProvider: { @Sendable in nowInstant() }
    )
}
// endregion

// region TES-A-116 block 4
func readSavedImage(at url: URL, with reader: SavedImageMrzReader<NSURL>, completion: @escaping (SavedImageScanResult?) -> Void) {
    reader.read(image: url as NSURL) { result, _ in completion(result) }
}
// endregion

// region TES-A-116 block 5
func describe(_ result: SavedImageScanResult) -> String {
    switch result.scan {
    case let decoded as MrzScanResultDecoded:
        return decoded.parse is ParseResult.Failure ? "MRZ-shaped text, not parseable" : "Read"
    case is MrzScanResultNoMrzFound:
        return "No MRZ in this image"
    case let failed as MrzScanResultCaptureError:
        return "Could not read: \(failed.error.code)"
    default:
        return ""
    }
}
// When you are done: reader.close()
// endregion

// region TES-A-116 block 6
func swaps(in result: SavedImageScanResult) -> [[String]] {
    result.candidates.map { candidate in
        candidate.disambiguations.map { swap in
            let from = Unicode.Scalar(swap.recognized).map { String(Character($0)) } ?? "?"
            let to = Unicode.Scalar(swap.resolved).map { String(Character($0)) } ?? "?"
            return "line \(swap.lineIndex) column \(swap.columnIndex): \(from) to \(to)"
        }
    }
}
// endregion
