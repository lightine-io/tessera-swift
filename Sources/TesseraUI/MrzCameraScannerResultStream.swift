import Foundation
import Tessera

// A Swift `AsyncStream` over the Kotlin camera scanner's `results` flow (TES-31): a small hand-written
// adapter instead of a code generator. It lives in TesseraUI because that is the Swift layer that ships;
// the `Tessera` product is a binary XCFramework and cannot carry Swift code.

extension MrzCameraScanner {
    /// The scanner's results as a Swift `AsyncStream`, one element per analysed frame or capture error.
    ///
    /// Use it in a `for await` loop instead of collecting the Kotlin `results` flow yourself:
    ///
    /// ```swift
    /// @MainActor func showResults(of scanner: AVCaptureMrzScanner) async {
    ///     for await result in scanner.resultStream {
    ///         label.text = "\(result)"
    ///     }
    /// }
    /// ```
    ///
    /// **Order.** Elements arrive in the order the scanner reported them. Nothing is dropped: the stream
    /// buffers every result until your loop reads it. The scanner already drops camera frames before
    /// analysis, so only a few results arrive each second.
    ///
    /// **Thread.** The loop body runs on the actor of the task that runs the loop. In a `@MainActor`
    /// function, a SwiftUI `.task`, or a `Task` started from main-actor code, each element is already on
    /// the main actor: update the UI directly, with no extra hop.
    ///
    /// **Start and end.** Each read of this property starts a new, separate collection of `results`, so
    /// keep one stream per loop. Read it before calling `start()`: results come from the moment you read
    /// it, and earlier results are not replayed. Results come only while the scanner runs, between
    /// `start()` and `stop()`. The stream does not end when the scanner stops or reports a
    /// capture error that ends its session, because a later `start()` reports more results on the same
    /// stream. To end it, cancel the task that runs the loop, or break out of the loop. The stream is not
    /// `Sendable`, because scan results are Kotlin objects: read this property inside the task that runs
    /// the loop.
    ///
    /// **Cancellation.** When the loop's task is cancelled, the loop ends at once. Kotlin cannot be
    /// cancelled from Swift, so the Kotlin collection behind the stream stops when the scanner reports its
    /// next result. While the scanner is stopped, that idle collection holds no camera resources and is
    /// released with the scanner.
    ///
    /// - Since: 0.5.3
    public var resultStream: AsyncStream<any MrzScanResult> {
        KotlinFlowStream.make(results, of: (any MrzScanResult).self)
    }
}

/// Builds an `AsyncStream` from a Kotlin `Flow`. Internal so tests can feed it a fake flow and observe when
/// the Kotlin collection ends.
enum KotlinFlowStream {
    /// Subscribes to `flow` before it returns and yields every value that is an `Element`, in order.
    /// Values of other types (and `nil`) are skipped. The stream finishes when the flow completes or fails.
    /// When the stream terminates (the consumer is cancelled or stops iterating), the next value the flow
    /// emits makes the collector throw a Kotlin `CancellationException`, which ends the Kotlin collection.
    /// `onCollectionEnd` runs once, after the Kotlin `collect` call returns.
    static func make<Element>(
        _ flow: any Kotlinx_coroutines_coreFlow,
        of _: Element.Type,
        onCollectionEnd: @escaping @Sendable () -> Void = {}
    ) -> AsyncStream<Element> {
        // Unbounded: a dropped element could be the one decoded reading, or the capture error that says the
        // session ended. The camera scanner analyses at most one frame every 200 ms, so the buffer grows
        // only while the consumer's actor is blocked, and cancelling the consumer ends the stream.
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: .unbounded)
        let collector = StreamCollector(continuation)
        continuation.onTermination = { _ in collector.stop() }
        // The completion-handler form, not `await`: Kotlin runs the collecting coroutine on this thread
        // until it first suspends, so a hot flow has its subscriber before this returns, and a result
        // reported right after (for example by `start()`) is not missed. The handler runs once, when
        // `collect` ends; once the collector has stopped, Kotlin ends it with a CancellationException, the
        // expected end.
        flow.collect(collector: collector) { _ in
            continuation.finish()
            onCollectionEnd()
        }
        return stream
    }
}

/// The Kotlin `FlowCollector` behind ``KotlinFlowStream``. Kotlin calls `emit` once at a time and waits for
/// it to return before the next value, so yields keep the flow's order. `@unchecked Sendable`: the only
/// mutable state is a lock-guarded flag, and each value is handed to the stream once and not touched again.
private final class StreamCollector<Element>: NSObject, Kotlinx_coroutines_coreFlowCollector, @unchecked Sendable {
    private let continuation: AsyncStream<Element>.Continuation
    private let lock = NSLock()
    private var stopped = false

    init(_ continuation: AsyncStream<Element>.Continuation) {
        self.continuation = continuation
    }

    /// Marks the collector stopped; the next `emit` ends the Kotlin collection.
    func stop() {
        lock.withLock { stopped = true }
    }

    func emit(value: Any?) async throws {
        if lock.withLock({ stopped }) { throw Self.kotlinCancellation() }
        // Kotlin hands each value over once and never touches it again; the scan results are immutable.
        guard let typed = value as? Element else { return }
        nonisolated(unsafe) let element = typed
        if case .terminated = continuation.yield(element) { throw Self.kotlinCancellation() }
    }

    /// An `NSError` carrying a Kotlin `CancellationException`, the form Kotlin/Native uses for that
    /// exception at the Objective-C boundary. Kotlin unwraps it and ends `collect` as a normal
    /// cancellation, not a failure, so upstream flow code sees the same signal it gets when a Kotlin
    /// collector is cancelled.
    private static func kotlinCancellation() -> NSError {
        NSError(
            domain: "KotlinException",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: "The Swift result stream ended.",
                "KotlinException": KotlinCancellationException(message: "The Swift result stream ended."),
            ]
        )
    }
}
