// Sample for TES-A-117 "Receive diagnostic events on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-117 block 1: Package.swift dependency lines

// region TES-A-117 block 2
import Foundation
import Tessera
// endregion

// region TES-A-117 block 3
final class FrameLog: NSObject, TelemetrySink {
    private let lock = NSLock()
    private var frames = 0

    func record(event: TelemetryEvent) {
        guard let frame = event as? CameraFrameEvent else { return }
        lock.lock()
        frames += 1
        let count = frames
        lock.unlock()
        print("\(event.name) #\(count): \(frame.outcome.name), \(frame.recognizedLineCount) lines, region found: \(frame.mrzRegionFound)")
    }
}
// endregion

// region TES-A-117 block 4
func makeScanner(log: FrameLog) -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.lenient,
        telemetry: log,
        cameraPosition: 1 // AVCaptureDevicePositionBack
    )
}
// endregion

// region TES-A-117 block 5
func masked(_ line: String) -> String {
    Redaction.shared.redactMrzLine(line: line)
}
// Letters and digits become *. The filler < and the length stay.
// endregion

// region TES-A-117 block 6
func registerAndMake() -> AVCaptureMrzScanner {
    let log = FrameLog()
    TelemetrySinkRegistry.shared.register(sink: log)
    return AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.lenient,
        telemetry: TelemetrySinkRegistry.shared.current,
        cameraPosition: 1
    )
}
// endregion
