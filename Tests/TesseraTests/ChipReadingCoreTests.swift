import Foundation
import Testing
@testable import Tessera

/// The core behind `ChipReading`, driven directly with plain values (`Int` updates, `String` ending),
/// because Swift code cannot build Kotlin update objects. No NFC needed.
struct ChipReadingCoreTests {
    typealias Core = ChipReadingCore<Int, String>

    private func collect(_ core: Core) async -> [Int] {
        var seen: [Int] = []
        for await value in core.updates { seen.append(value) }
        return seen
    }

    @Test func updatesArriveInOrderAndTheStreamFinishesAfterTheEnding() async {
        let core = Core()
        core.deliver(1); core.deliver(2); core.deliver(3)
        core.finish("done")
        #expect(await collect(core) == [1, 2, 3])
    }

    @Test func updatesAfterTheEndingAndASecondEndingAreIgnored() async {
        let core = Core()
        core.deliver(1)
        core.finish("first")
        core.deliver(2)
        core.finish("second")
        #expect(await collect(core) == [1])
        #expect(await core.awaitEnding() == "first")
    }

    @Test func endingAwaitedBeforeItHappensAndAfter() async throws {
        let core = Core()
        let before = Task { await core.awaitEnding() }
        try await Task.sleep(nanoseconds: 30_000_000) // let the waiter park
        core.finish("done")
        #expect(await before.value == "done")
        #expect(await core.awaitEnding() == "done") // after
    }

    @Test func endingAwaitedWhileUpdatesAreStillComing() async throws {
        let core = Core()
        let consumer = Task { await collect(core) }
        let waiter = Task { await core.awaitEnding() }
        for value in 1...50 {
            core.deliver(value)
            if value % 10 == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
        }
        core.finish("done")
        #expect(await consumer.value == Array(1...50))
        #expect(await waiter.value == "done")
    }

    @Test func manyAwaitersAllGetTheSameEnding() async throws {
        let core = Core()
        let early = (0..<20).map { _ in Task { await core.awaitEnding() } }
        try await Task.sleep(nanoseconds: 30_000_000)
        core.finish("done")
        let late = (0..<20).map { _ in Task { await core.awaitEnding() } }
        for task in early + late { #expect(await task.value == "done") }
    }

    @Test func aConsumerThatStartsLateLosesNothing() async {
        let core = Core()
        for value in 0..<2_000 { core.deliver(value) }
        core.finish("done")
        // The loop starts only now, long after the producer finished.
        #expect(await collect(core) == Array(0..<2_000))
    }

    @Test func aSlowConsumerNeverBlocksTheProducerAndMissesNothing() async throws {
        let core = Core()
        let producerDone = Locked(false)
        let producer = Thread {
            for value in 0..<5_000 { core.deliver(value) }
            core.finish("done")
            producerDone.withLock { $0 = true }
        }
        producer.start()
        // The consumer has not started, yet the producer must finish on its own.
        #expect(try await waitUntil { producerDone.withLock { $0 } })
        var seen: [Int] = []
        for await value in core.updates {
            seen.append(value)
            if seen.count % 1_000 == 0 { try await Task.sleep(nanoseconds: 5_000_000) } // slow
        }
        #expect(seen == Array(0..<5_000)) // every update, in order, then the stream finished
        #expect(await core.awaitEnding() == "done")
    }

    @Test func cancelBeforeTheHandleExistsReachesItOnceWhenAttached() {
        let core = Core()
        core.cancel(); core.cancel()
        let handle = FakeHandle()
        core.attach(handle)
        core.cancel()
        #expect(handle.cancelCount == 1)
    }

    @Test func cancelIsIdempotentAndReachesTheHandleOnceFromManyThreads() async {
        let core = Core()
        let handle = FakeHandle()
        core.attach(handle)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { core.cancel() } }
        }
        #expect(handle.cancelCount == 1)
    }

    @Test func cancelAfterTheEndingDoesNothing() {
        let core = Core()
        let handle = FakeHandle()
        core.attach(handle)
        core.finish("done")
        core.cancel()
        #expect(handle.cancelCount == 0)
    }

    @Test func aHandleAttachedAfterTheEndingIsIgnored() {
        let core = Core()
        core.finish("done") // a read that could not start ends before start() returns
        let handle = FakeHandle()
        core.attach(handle)
        core.cancel()
        #expect(handle.cancelCount == 0)
    }

    @Test func theObserverIsHeldUntilTheEndingAndNotAfter() {
        let core = Core()
        weak var weakObserver: NSObject?
        do {
            let observer = NSObject()
            weakObserver = observer
            core.retain(observer)
        }
        #expect(weakObserver != nil) // only the core holds it now
        core.finish("done")
        #expect(weakObserver == nil)
    }
}
