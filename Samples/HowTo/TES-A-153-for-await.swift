// Sample for TES-A-153 "Get scan results with for await on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-153 block 1: Package.swift dependency lines

// region TES-A-153 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

// region TES-A-153 block 3
func makeScanner() -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.lenient,
        telemetry: TelemetrySinkRegistry.shared.current,
        cameraPosition: 1 // AVCaptureDevicePositionBack
    )
}
// endregion

// region TES-A-153 block 4
struct ScanView: View {
    @State private var note = "Looking for an MRZ"

    var body: some View {
        Text(note)
            .task { await scan() }
    }

    private func scan() async {
        let scanner = makeScanner()
        let results = scanner.resultStream
        scanner.start()
        for await result in results {
            if let decoded = result as? MrzScanResultDecoded,
               !(decoded.parse is ParseResult.Failure) {
                note = "Read"   // already on the main actor
                break
            }
            if let capture = result as? MrzScanResultCaptureError {
                note = "Camera: \(capture.error.code)"
            }
        }
        scanner.stop()
        scanner.close()
    }
}
// endregion

/// Namespace: TES-A-18 declares a top-level CameraReader of its own.
enum ForAwait {
    // region TES-A-153 block 5
    @MainActor
    final class CameraReader {
        private(set) var lastCode: String?

        func run(_ scanner: AVCaptureMrzScanner) async {
            let results = scanner.resultStream
            scanner.start()
            for await result in results {
                if let capture = result as? MrzScanResultCaptureError { lastCode = capture.error.code }
            }
            scanner.stop()
        }
    }
    // endregion
}
