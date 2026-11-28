import Foundation
import os
import Tessera

/// A telemetry sink that prints each SDK diagnostic event to Apple's unified log, so you can read it
/// in Console or the Xcode debug console while you debug.
///
/// This is opt-in and for debugging. It lives in its own product, `TesseraLogging`; the `Tessera` and
/// `TesseraUI` products never write to the log. Add the product to your app on purpose, then register
/// the sink once at startup:
///
/// ```swift
/// TelemetrySinkRegistry.shared.register(sink: LoggingTelemetrySink())
/// ```
///
/// Each event becomes one line at debug level: the event's `name`, a space, then its description
/// text. The text is logged as public, so it is readable without a debugger attached. The SDK's own
/// events hold no document data. An event type of your own prints whatever its description returns, so
/// keep personal data out of it.
///
/// - Since: 1.2.0
public final class LoggingTelemetrySink: NSObject, TelemetrySink, @unchecked Sendable {
    // Immutable after init, and `Logger` is safe to use from any thread.
    private let logger: Logger

    /// Creates the sink. Lines go to `subsystem` and `category` in the unified log.
    public init(subsystem: String = "io.lightine.tessera", category: String = "telemetry") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// Writes one debug line for the event: its `name`, a space, and its description text.
    public func record(event: any TelemetryEvent) {
        let line = Self.line(for: event)
        logger.debug("\(line, privacy: .public)")
    }

    /// The text of one log line, kept apart from the log call so a test can check it.
    static func line(for event: any TelemetryEvent) -> String {
        "\(event.name) \(String(describing: event))"
    }
}
