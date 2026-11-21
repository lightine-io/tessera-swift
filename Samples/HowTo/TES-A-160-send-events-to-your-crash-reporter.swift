// Sample for TES-A-160 "Send Tessera diagnostic events to your own crash reporter on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-160 block 1: Package.swift dependency lines

// The last block needs AVFoundation; the page says so after it.
import AVFoundation

// region TES-A-160 block 2
import Foundation
import Tessera
// endregion

// region TES-A-160 block 3
protocol CrashReporter {
    func breadcrumb(category: String, message: String, data: [String: String])
}

struct PrintReporter: CrashReporter {
    func breadcrumb(category: String, message: String, data: [String: String]) {
        // your crash reporter's breadcrumb call goes here
        let fields = data.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        print("\(category) | \(message) | \(fields)")
    }
}
// endregion

// region TES-A-160 block 4
final class CrashReporterSink: NSObject, TelemetrySink {
    private let reporter: CrashReporter
    private let lock = NSLock()
    private var lastOutcome: CameraFrameOutcome?

    init(reporter: CrashReporter) {
        self.reporter = reporter
    }

    func record(event: any TelemetryEvent) {
        guard let frame = event as? CameraFrameEvent else { return }
        lock.lock()
        let changed = lastOutcome != frame.outcome
        lastOutcome = frame.outcome
        lock.unlock()
        guard changed else { return }
        reporter.breadcrumb(
            category: event.name,
            message: frame.outcome.name,
            data: [
                "recognizedLineCount": String(frame.recognizedLineCount),
                "mrzRegionFound": String(frame.mrzRegionFound),
                "ocrConfidence": frame.ocrConfidence.map { String($0.floatValue) } ?? "none",
                "detectedFormat": frame.detectedFormat?.name ?? "none",
            ]
        )
    }
}
// endregion

// region TES-A-160 block 5
func registerCrashReporting(reporter: CrashReporter) {
    TelemetrySinkRegistry.shared.register(sink: CrashReporterSink(reporter: reporter))
}
// endregion

// region TES-A-160 block 6
func forwardParse(_ reporter: CrashReporter, _ result: ParseResult) {
    guard let failure = result as? ParseResult.Failure else { return }
    reporter.breadcrumb(
        category: "tessera.parse",
        message: failure.error.description_,
        data: ["readMethod": failure.metadata.readMethod.name]
    )
}

func parseDemo() {
    let now = KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_700_000_000_000)
    forwardParse(PrintReporter(), MrzParser.shared.parse(input: "ABC", referenceTime: now))
}
// endregion

// region TES-A-160 block 8
func forwardResult(_ reporter: CrashReporter, _ result: MrzScanResult) {
    switch result {
    case let captureError as MrzScanResultCaptureError:
        reporter.breadcrumb(category: "tessera.camera", message: captureError.error.code, data: [:])
    case let decoded as MrzScanResultDecoded:
        forwardParse(reporter, decoded.parse)
    default:
        break   // MrzScanResultNoMrzFound: the normal outcome between reads
    }
}
// endregion

// region TES-A-160 block 9
func demo() {
    let reporter = PrintReporter()
    let sink = CrashReporterSink(reporter: reporter)
    sink.record(event: CameraFrameEvent(
        outcome: CameraFrameOutcome.ocrFailed,
        recognizedLineCount: 0,
        mrzRegionFound: false,
        ocrConfidence: nil,
        detectedFormat: nil
    ))
    let quality = ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 0)
    let capture = MrzScanResultCaptureError(error: CameraErrorOcrFailed(message: "engine failed"), quality: quality)
    forwardResult(reporter, capture)
}
// endregion

// region TES-A-160 block 11
func makeScanner(reporter: CrashReporter) -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.lenient,
        telemetry: CrashReporterSink(reporter: reporter),
        cameraPosition: 1 // AVCaptureDevicePositionBack
    )
}
// endregion
