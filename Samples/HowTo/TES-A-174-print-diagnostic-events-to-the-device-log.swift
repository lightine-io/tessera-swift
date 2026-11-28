// Sample for TES-A-174 "Print diagnostic events to the device log on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-174 block 1: Package.swift dependency lines

// region TES-A-174 block 2
import Tessera
import TesseraLogging
// endregion

// region TES-A-174 block 3
func startEventLog() {
    TelemetrySinkRegistry.shared.register(sink: LoggingTelemetrySink())
}
// endregion

// region TES-A-174 block 4
func makeLoggedScanner() -> AVCaptureMrzScanner {
    AVCaptureMrzScanner(
        recognizer: VisionMrzTextRecognizer(),
        mode: ParsingMode.lenient,
        telemetry: TelemetrySinkRegistry.shared.current,
        cameraPosition: 1 // AVCaptureDevicePositionBack
    )
}
// endregion

// region TES-A-174 block 6
func startEventLog(for feature: String) {
    TelemetrySinkRegistry.shared.register(
        sink: LoggingTelemetrySink(subsystem: "com.example.myapp", category: feature)
    )
}
// endregion
