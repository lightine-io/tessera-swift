// Sample for TES-A-118 "Restrict OCR to the MRZ band on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-118 block 1: Package.swift dependency lines

// region TES-A-118 block 2
import Tessera
// endregion

// region TES-A-118 block 3
func makeRecognizer() -> VisionMrzTextRecognizer {
    let recognizer = VisionMrzTextRecognizer()
    recognizer.restrictToMrzBand()
    return recognizer
}
// endregion

// region TES-A-118 block 4
func makeScanner(recognizer: VisionMrzTextRecognizer) -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: recognizer,
        mode: ParsingMode.lenient,
        telemetry: NoOpTelemetrySink(),
        cameraPosition: 1 // AVCaptureDevicePositionBack
    )
}
// endregion

// region TES-A-118 block 5
func follow(_ recognizer: VisionMrzTextRecognizer, region: CGRect) {
    recognizer.restrictToMrzBand(x: region.origin.x, y: region.origin.y, width: region.size.width, height: region.size.height)
}
// endregion
