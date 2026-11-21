// Sample for TES-A-18 "Read an MRZ from the live camera on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Swift 5 language mode, as the page's "Before you start" states. In Swift 6 mode block 5 does not compile.
// skip TES-A-18 block 1: Package.swift dependency lines

// region TES-A-18 block 2
import AVFoundation
import Tessera

final class ResultCollector: NSObject, Kotlinx_coroutines_coreFlowCollector {
    private let onResult: (MrzScanResult) -> Void
    init(_ onResult: @escaping (MrzScanResult) -> Void) { self.onResult = onResult }

    func emit(value: Any?) async throws {
        if let result = value as? MrzScanResult { onResult(result) }
    }
}
// endregion

// region TES-A-18 block 3
@MainActor
final class CameraReader: ObservableObject {
    @Published var note = "Not started"
    var scanner: AVCaptureMrzScanner?
    var collectTask: Task<Void, Never>?
}
// endregion

// region TES-A-18 block 4
extension CameraReader {
    func begin() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in self?.startScanner() }   // also on "no"
            }
        } else {
            startScanner()
        }
    }
}
// endregion

// region TES-A-18 block 5
extension CameraReader {
    func startScanner() {
        let scanner = AVCaptureMrzScanner(
            recognizer: VisionMrzTextRecognizer(),
            mode: ParsingMode.lenient,
            telemetry: NoOpTelemetrySink(),
            cameraPosition: 1 // AVCaptureDevicePositionBack
        )
        self.scanner = scanner
        let collector = ResultCollector { [weak self] result in
            Task { @MainActor in self?.handle(result) }   // hop to the main actor
        }
        collectTask = Task { try? await scanner.results.collect(collector: collector) }
        scanner.start()
    }
}
// endregion

// region TES-A-18 block 6
extension CameraReader {
    func handle(_ result: MrzScanResult) {
        switch result {
        case let decoded as MrzScanResultDecoded:
            note = decoded.parse is ParseResult.Failure ? "MRZ-shaped text, not parseable" : "Read"
        case let capture as MrzScanResultCaptureError:
            note = "Camera: \(capture.error.code)"
        default:
            break   // MrzScanResultNoMrzFound: the normal outcome between reads
        }
    }
}
// endregion

// region TES-A-18 block 7
extension CameraReader {
    func finish() {
        collectTask?.cancel()
        scanner?.stop()
        scanner?.close()
        scanner = nil
    }
}
// endregion

// region TES-A-18 block 8
func makeStrictScanner() -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.strict,
        telemetry: TelemetrySinkRegistry.shared.current,
        cameraPosition: 1
    )
}
// endregion
