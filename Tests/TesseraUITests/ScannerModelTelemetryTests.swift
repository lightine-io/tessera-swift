import Tessera
import Testing
@testable import TesseraUI

/// Host tests for TES-196: the scanner screen sends its camera events to the sink the app registered with
/// `TelemetrySinkRegistry`, as the Android screen does. A frame cannot be driven on the host (the live scanner
/// needs the camera and Vision), so these check the one lookup both scanner constructions in ``ScannerModel``
/// use. The registry is process-wide, so the suite runs serially and resets it afterwards.
@MainActor
@Suite(.serialized)
struct ScannerModelTelemetryTests {
    private final class RecordingSink: TelemetrySink {
        private(set) var names: [String] = []
        func record(event: any TelemetryEvent) { names.append(event.name) }
    }

    @Test func theModelUsesTheSinkTheAppRegistered() {
        let sink = RecordingSink()
        TelemetrySinkRegistry.shared.register(sink: sink)
        defer { TelemetrySinkRegistry.shared.reset() }

        let resolved = ScannerModel.registeredTelemetrySink()
        #expect(resolved === sink)

        resolved.record(event: CameraFrameEvent(
            outcome: CameraFrameOutcome.noMrzFound,
            recognizedLineCount: 0,
            mrzRegionFound: false,
            ocrConfidence: nil,
            detectedFormat: nil
        ))
        #expect(sink.names == ["mrz.camera.frame"])
    }

    @Test func theModelDiscardsEventsWhenNothingIsRegistered() {
        TelemetrySinkRegistry.shared.reset()
        #expect(ScannerModel.registeredTelemetrySink() is NoOpTelemetrySink)
    }
}
