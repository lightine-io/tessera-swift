// Sample for TES-A-122 "Swap the OCR engine on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-122 block 1: Package.swift dependency lines

// region TES-A-122 block 2
import Foundation
import Tessera
// endregion

// region TES-A-122 block 3
final class TimedRecognizer: NSObject, MrzTextRecognizer, KotlinAutoCloseable {
    private let engine = VisionMrzTextRecognizer()

    func recognize(frame: Any?) async throws -> RecognizedText {
        guard let frame else { return RecognizedText(lines: []) }
        let start = Date()
        defer { print("OCR took \(Date().timeIntervalSince(start)) s") }
        return try await engine.recognize(frame: frame)
    }

    func close() { engine.close() }
}
// endregion

/// Namespace: TES-A-153 declares a top-level makeScanner() of its own.
struct SwapTheOcrEngine {
    // region TES-A-122 block 4
    func makeScanner() -> AVCaptureMrzScanner {
        AVCaptureMrzScanner(
            recognizer: TimedRecognizer(),
            mode: ParsingMode.lenient,
            telemetry: NoOpTelemetrySink(),
            cameraPosition: 1 // AVCaptureDevicePositionBack
        )
    }
    // endregion
}
