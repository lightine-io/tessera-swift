import Foundation
import Tessera
@testable import TesseraKit

// The package supports iOS 15: thread-safe state uses an `NSLock`, not `Mutex` (iOS 18), and waits use
// `Task.sleep(nanoseconds:)`, not `Duration` (iOS 16).

/// A value behind an `NSLock`.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// A stand-in for the Kotlin read handle: counts `cancel()` calls.
final class FakeHandle: NSObject, ChipReadHandle, @unchecked Sendable {
    private let cancels = Locked(0)
    var cancelCount: Int { cancels.withLock { $0 } }
    var isEnded: Bool { false }
    func cancel() { cancels.withLock { $0 += 1 } }
}

/// Polls until `condition` holds or `limitSeconds` pass. A bounded wait, not a fixed sleep.
func waitUntil(limitSeconds: Double = 30, _ condition: () -> Bool) async throws -> Bool {
    let deadline = Date().addingTimeInterval(limitSeconds)
    while Date() < deadline {
        if condition() { return true }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

/// Real Kotlin updates and a real ending, captured once from the real reader. The simulator has no
/// NFC, so the reader ends at once with `NotStarted`; Swift code cannot build these objects itself.
enum RealReading {
    /// One real read for the whole run: the reader allows one read at a time, so starting one per
    /// test would make the others end with `READ_IN_PROGRESS`.
    private static let shared = Task { try await capture() }

    static func sample() async throws -> Sample {
        try await shared.value
    }

    /// The Swift snapshots and finish of the real read; `raw` holds the Kotlin objects.
    struct Sample: @unchecked Sendable {
        let updates: [ChipReadSnapshot]
        let ending: ChipReadFinish
        var rawUpdates: [ChipReadUpdate] { updates.compactMap(\.raw) }
        var rawEnding: ChipReadEnding { ending.raw! }
    }

    private static func capture() async throws -> Sample {
        let key = try ChipAccessKey.fromCan("123456")
        let options = try ChipReadOptions.Builder(accessKey: key).build()
        let reading = ChipReading.start(options: options)
        var updates: [ChipReadSnapshot] = []
        for await update in reading.updates { updates.append(update) }
        return Sample(updates: updates, ending: await reading.ending)
    }
}
