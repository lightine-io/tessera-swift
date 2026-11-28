import Tessera
import Testing
@testable import TesseraLogging

/// `LoggingTelemetrySink`: the line text is checked directly; the system log is not read.
struct LoggingTelemetrySinkTests {
    private final class FakeEvent: TelemetryEvent, CustomStringConvertible {
        let name = "fake.event"
        let description = "FakeEvent(step=3)"
    }

    @Test func theLineIsTheNameThenTheDescription() {
        #expect(LoggingTelemetrySink.line(for: FakeEvent()) == "fake.event FakeEvent(step=3)")
    }

    /// A real SDK event comes from Kotlin: its description is the Kotlin `toString()`, the same text
    /// the Android and JVM helper prints.
    @Test func aRealSdkEventPrintsItsKotlinText() {
        let event = CameraFrameEvent(
            outcome: CameraFrameOutcome.noMrzFound,
            recognizedLineCount: 0,
            mrzRegionFound: false,
            ocrConfidence: nil,
            detectedFormat: nil,
            fillerPaddingAdded: 0
        )
        let line = LoggingTelemetrySink.line(for: event)
        #expect(line.hasPrefix("mrz.camera.frame CameraFrameEvent(outcome="))
        #expect(line.contains("recognizedLineCount=0, mrzRegionFound=false"))
    }

    @Test func theDefaultInitializerWorksAndRecordingDoesNotCrash() {
        let sink = LoggingTelemetrySink()
        sink.record(event: FakeEvent())
        let custom = LoggingTelemetrySink(subsystem: "test.subsystem", category: "test")
        custom.record(event: FakeEvent())
    }
}
