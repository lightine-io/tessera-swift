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

    @Test func theDefaultInitializerWorksAndRecordingDoesNotCrash() {
        let sink = LoggingTelemetrySink()
        sink.record(event: FakeEvent())
        let custom = LoggingTelemetrySink(subsystem: "test.subsystem", category: "test")
        custom.record(event: FakeEvent())
    }
}
