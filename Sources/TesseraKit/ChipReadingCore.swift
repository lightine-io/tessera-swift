import Foundation
import Tessera

/// The state machine behind ``ChipReading``: the update buffer, the one ending, the waiters and the
/// cancel flag. It is generic over the update and ending types so the tests can drive it with plain
/// values, because Swift code cannot build the Kotlin update and ending objects.
///
/// `@unchecked Sendable`, and truly needed: every mutable field sits behind one `NSLock`. A Swift
/// `final class` with immutable fields cannot hold this state, and `Mutex` needs iOS 18 while the
/// package supports iOS 15.
final class ChipReadingCore<Update: Sendable, Ending: Sendable>: @unchecked Sendable {
    /// The updates, in the order they were delivered. Finishes right after the ending.
    ///
    /// The buffer is unbounded on purpose. A read sends about one update per chunk of a file, a few
    /// hundred in all, and each is a small object. A bounded buffer would have to drop something, and
    /// a dropped element could be a state change or, worse for the consumer, the last update before
    /// the finish. Memory only grows while the consumer does not read, and a read lasts seconds.
    let updates: AsyncStream<Update>

    private let continuation: AsyncStream<Update>.Continuation
    private let lock = NSLock()
    private var handle: (any ChipReadHandle)?
    private var cancelRequested = false
    private var cancelSent = false
    private var ending: Ending?
    private var waiters: [CheckedContinuation<Ending, Never>] = []
    /// The observer, kept alive until the ending (the Kotlin side may hold it weakly).
    private var retainedObserver: AnyObject?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Update.self, bufferingPolicy: .unbounded)
        self.updates = stream
        self.continuation = continuation
    }

    /// Keeps `observer` alive until the ending. Call it before the read starts.
    func retain(_ observer: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        if ending == nil { retainedObserver = observer }
    }

    /// Stores the read's handle. A cancel that came before this is sent now, once.
    func attach(_ newHandle: any ChipReadHandle) {
        lock.lock()
        if ending != nil {
            lock.unlock()
            return
        }
        handle = newHandle
        let sendNow = cancelRequested && !cancelSent
        if sendNow { cancelSent = true }
        lock.unlock()
        if sendNow { newHandle.cancel() }
    }

    /// Passes one update on. Updates after the ending are dropped.
    func deliver(_ update: Update) {
        lock.lock()
        defer { lock.unlock() }
        if ending == nil { continuation.yield(update) }
    }

    /// Records the one ending, wakes every waiter, finishes the stream and lets go of the observer
    /// and the handle. A second ending is ignored.
    func finish(_ newEnding: Ending) {
        lock.lock()
        if ending != nil {
            lock.unlock()
            return
        }
        ending = newEnding
        let woken = waiters
        waiters = []
        handle = nil
        let observer = retainedObserver
        retainedObserver = nil
        continuation.finish()
        lock.unlock()
        for waiter in woken { waiter.resume(returning: newEnding) }
        withExtendedLifetime(observer) {}
    }

    /// Asks the read to stop. Safe to call again and from any thread: the handle gets one `cancel()`.
    func cancel() {
        lock.lock()
        if ending != nil || cancelSent {
            lock.unlock()
            return
        }
        cancelRequested = true
        guard let target = handle else {
            lock.unlock()
            return // attach() sends it
        }
        cancelSent = true
        lock.unlock()
        target.cancel()
    }

    /// The ending, now if it happened, otherwise when it does.
    func awaitEnding() async -> Ending {
        await withCheckedContinuation { (waiter: CheckedContinuation<Ending, Never>) in
            lock.lock()
            if let done = ending {
                lock.unlock()
                waiter.resume(returning: done)
            } else {
                waiters.append(waiter)
                lock.unlock()
            }
        }
    }
}
