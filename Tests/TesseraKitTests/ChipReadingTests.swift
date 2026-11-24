import Foundation
import Testing
import Tessera
@testable import TesseraKit

/// `ChipReading` itself, with a fake starter that hands out the observer. The updates and the ending
/// are real Kotlin objects, captured once from the real reader on the simulator (see `RealReading`).
struct ChipReadingTests {
    /// A fake read: keeps the observer weakly, so the tests can see who else holds it.
    private final class Fake: @unchecked Sendable {
        let handle = FakeHandle()
        private let slot = Locked<(any ChipReadObserver)?>(nil)
        weak var weakObserver: AnyObject?
        func starter(_ observer: any ChipReadObserver) -> any ChipReadHandle {
            weakObserver = observer as AnyObject
            slot.withLock { $0 = observer }
            return handle
        }
        var observer: any ChipReadObserver { slot.withLock { $0! } }
        func forgetObserver() { slot.withLock { $0 = nil } }
    }

    @Test func updatesThenEndingThroughTheObserver() async throws {
        let real = try await RealReading.sample()
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        let observer = fake.observer
        for update in real.updates { observer.onUpdate(update: update) }
        observer.onEnding(ending: real.ending)

        var count = 0
        for await _ in reading.updates { count += 1 }
        #expect(count == real.updates.count)
        let ending = await reading.ending
        #expect(ending === real.ending)
    }

    @Test func nothingHoldsTheObserverAfterTheEnding() async throws {
        let real = try await RealReading.sample()
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        fake.observer.onUpdate(update: try #require(real.updates.first))
        fake.forgetObserver() // the fake stands for Kotlin letting go: only ChipReading holds it now
        #expect(fake.weakObserver != nil)
        do { // a scope, so this strong reference is gone before the check
            let observer = fake.weakObserver as? any ChipReadObserver
            observer?.onEnding(ending: real.ending)
        }
        _ = await reading.ending
        #expect(fake.weakObserver == nil)
    }

    @Test func cancelReachesTheHandleOnce() {
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        reading.cancel(); reading.cancel(); reading.cancel()
        #expect(fake.handle.cancelCount == 1)
    }

    @Test func resultCancelsTheReadWhenItsTaskIsCancelled() async throws {
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        let task = Task { await reading.result() }
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(fake.handle.cancelCount == 0)
        task.cancel()
        #expect(try await waitUntil { fake.handle.cancelCount == 1 })
        // The read ends the way Kotlin ends a cancelled read; here the real ending stands in for it.
        let real = try await RealReading.sample()
        fake.observer.onEnding(ending: real.ending)
        #expect(await task.value === real.ending)
    }

    @Test func cancellingTheTaskOfAnUpdatesLoopDoesNotCancelTheRead() async throws {
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        let loop = Task { for await _ in reading.updates {} }
        try await Task.sleep(nanoseconds: 30_000_000)
        loop.cancel()
        await loop.value // the loop ended for this consumer
        #expect(fake.handle.cancelCount == 0)
    }

    @Test func awaitingTheEndingTwiceFromTwoTasksWorks() async throws {
        let real = try await RealReading.sample()
        let fake = Fake()
        let reading = ChipReading(starter: fake.starter)
        let a = Task { await reading.ending }
        let b = Task { await reading.ending }
        try await Task.sleep(nanoseconds: 30_000_000)
        fake.observer.onEnding(ending: real.ending)
        #expect(await a.value === real.ending)
        #expect(await b.value === real.ending)
        #expect(await reading.ending === real.ending)
    }

    @Test func aReadThatEndsInsideStartStillDeliversItsEnding() async throws {
        let real = try await RealReading.sample()
        let handle = FakeHandle()
        let reading = ChipReading { observer in
            observer.onEnding(ending: real.ending) // the way a read that cannot start behaves
            return handle
        }
        #expect(await reading.ending === real.ending)
        reading.cancel()
        #expect(handle.cancelCount == 0)
    }
}
