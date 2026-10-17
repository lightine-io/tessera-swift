import Foundation
import Synchronization
import Testing
import Tessera
@testable import TesseraUI

/// `MrzCameraScanner.resultStream` and the `KotlinFlowStream` adapter behind it (TES-31): order, main-actor
/// delivery to a main-actor loop, and that ending the loop ends the Kotlin collection.
@MainActor
struct ResultStreamTests {
    /// A result tagged with `tag` in `recognizedLineCount`, so a test can check the order.
    private static func result(_ tag: Int32) -> any MrzScanResult {
        MrzScanResultCaptureError(
            error: CameraErrorOcrFailed(message: "synthetic"),
            quality: ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: tag)
        )
    }

    /// Polls until `condition` holds or `limit` passes. A bounded wait, not a fixed sleep.
    private func waitUntil(
        limit: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func elementsArriveInOrderOnTheMainActor() async throws {
        let flow = FakeFlow()
        let seen = Recorder()
        let consumer = Task { @MainActor in
            let stream = KotlinFlowStream.make(flow, of: (any MrzScanResult).self)
            for await result in stream { seen.record(result) }
        }
        // The fake emits from a background thread, the way a Swift `async` collector runs.
        for tag in Int32(1)...20 { flow.send(Self.result(tag)) }
        let gotAll = try await waitUntil { seen.tags.count == 20 }
        consumer.cancel()

        #expect(gotAll)
        #expect(seen.tags == Array(1...20))
        #expect(seen.allOnMain, "a main-actor loop gets every element on the main thread, with no hop of its own")
    }

    @Test func skipsValuesOfOtherTypes() async throws {
        let flow = FakeFlow()
        let seen = Recorder()
        let consumer = Task { @MainActor in
            let stream = KotlinFlowStream.make(flow, of: (any MrzScanResult).self)
            for await result in stream { seen.record(result) }
        }
        flow.send("not a result")
        flow.send(nil)
        flow.send(Self.result(7))
        let got = try await waitUntil { seen.tags.count == 1 }
        consumer.cancel()

        #expect(got)
        #expect(seen.tags == [7])
    }

    @Test func cancellingTheLoopStopsTheKotlinCollection() async throws {
        let flow = FakeFlow()
        let ended = Flag()
        let seen = Recorder()
        let consumer = Task { @MainActor in
            let stream = KotlinFlowStream.make(flow, of: (any MrzScanResult).self) { ended.set() }
            for await result in stream { seen.record(result) }
        }
        flow.send(Self.result(1))
        #expect(try await waitUntil { seen.tags == [1] })

        consumer.cancel()
        await consumer.value // the loop ends at once, before the flow emits again
        #expect(!ended.isSet, "Kotlin cannot be cancelled from Swift: it ends on the next value")

        flow.send(Self.result(2))
        let collectionEnded = try await waitUntil { flow.collectEnded && ended.isSet }

        #expect(collectionEnded, "the next value after cancellation ends the collection")
        #expect(flow.emitError?.domain == "KotlinException")
        #expect(flow.emitError?.userInfo["KotlinException"] is KotlinCancellationException)
        #expect(seen.tags == [1], "nothing reaches the loop after it is cancelled")
    }

    @Test func breakingOutOfTheLoopStopsTheKotlinCollection() async throws {
        let flow = FakeFlow()
        let consumer = Task { @MainActor in
            for await _ in KotlinFlowStream.make(flow, of: (any MrzScanResult).self) { break }
        }
        flow.send(Self.result(1))
        await consumer.value
        flow.send(Self.result(2))
        #expect(try await waitUntil { flow.collectEnded })
    }

    @Test func theStreamFinishesWhenTheFlowCompletes() async throws {
        let flow = FakeFlow()
        let seen = Recorder()
        let consumer = Task { @MainActor in
            for await _ in KotlinFlowStream.make(flow, of: (any MrzScanResult).self) {}
            seen.finished = true
        }
        flow.send(Self.result(1))
        flow.complete()
        #expect(try await waitUntil { seen.finished })
        consumer.cancel()
    }
}


/// A thread-safe flag a `@Sendable` callback can set.
private final class Flag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}

/// What a test's main-actor loop saw.
@MainActor
private final class Recorder {
    var results: [any MrzScanResult] = []
    var allOnMain = true
    var finished = false
    var tags: [Int32] { results.map { ($0 as? MrzScanResultCaptureError)?.quality.recognizedLineCount ?? -1 } }

    func record(_ result: any MrzScanResult) {
        allOnMain = allOnMain && Thread.isMainThread
        results.append(result)
    }
}

/// A Swift stand-in for a Kotlin `Flow`: values sent with ``send(_:)`` are emitted one at a time, in order,
/// from the collecting task (off the main actor). Records the error the collector throws, if any.
private final class FakeFlow: NSObject, Kotlinx_coroutines_coreFlow, @unchecked Sendable {
    private enum Event: @unchecked Sendable { case value(Any?), complete }
    private let events: AsyncStream<Event>
    private let input: AsyncStream<Event>.Continuation
    private let state = Mutex<(ended: Bool, error: NSError?)>((false, nil))

    override init() {
        (events, input) = AsyncStream.makeStream(of: Event.self)
    }

    func send(_ value: Any?) { input.yield(.value(value)) }
    func complete() { input.yield(.complete) }

    var collectEnded: Bool { state.withLock { $0.ended } }
    var emitError: NSError? { state.withLock { $0.error } }

    func collect(collector: any Kotlinx_coroutines_coreFlowCollector) async throws {
        defer { state.withLock { $0.ended = true } }
        for await event in events {
            switch event {
            case .complete:
                return
            case let .value(value):
                do {
                    try await collector.emit(value: value)
                } catch {
                    state.withLock { $0.error = error as NSError }
                    throw error
                }
            }
        }
    }
}
