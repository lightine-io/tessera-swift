// Sample for TES-A-114 "Read capture metadata from a saved image on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// nowInstant() comes from TES-A-116, as the page's "Before you start" says.
// skip TES-A-114 block 1: Package.swift dependency lines

// region TES-A-114 block 2
import Foundation
import Tessera
// endregion

// region TES-A-114 block 3
func makeReaderWithMetadata() -> SavedImageMrzReader<NSURL> {
    let acknowledgement = SavedImageReadingAcknowledgement()
    return SavedImageMrzReader<NSURL>(
        acknowledgement: acknowledgement,
        recognizer: VisionSavedImageRecognizerKt.visionSavedImageRecognizer(acknowledgement: acknowledgement),
        mode: ParsingMode.lenient,
        tolerant: false,
        metadataReader: ImageIoCaptureMetadataReaderKt.imageIoCaptureMetadataReader(acknowledgement: acknowledgement),
        metadataPolicy: CaptureMetadataPolicy.excludingLocation,
        telemetry: NoOpTelemetrySink(),
        referenceTimeProvider: { @Sendable in nowInstant() }
    )
}
// endregion

// region TES-A-114 block 4
func device(for url: URL, with reader: SavedImageMrzReader<NSURL>, completion: @escaping (String?) -> Void) {
    reader.read(image: url as NSURL) { result, _ in
        let metadata = result?.captureMetadata
        completion(metadata.map { "\($0.deviceMake ?? "?") \($0.deviceModel ?? "?")" })
    }
}
// endregion

// region TES-A-114 block 5
func readLocation(of url: URL) {
    let acknowledgement = SavedImageReadingAcknowledgement()
    let reader = ImageIoCaptureMetadataReaderKt.imageIoCaptureMetadataReader(acknowledgement: acknowledgement)
    reader.read(image: url as NSURL, policy: CaptureMetadataPolicy.includingLocation) { metadata, _ in
        _ = metadata?.location   // precise location: ask only if you need it
    }
}
// endregion
