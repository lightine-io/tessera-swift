import Foundation
import Tessera

// TEST AID. Nothing here talks to NFC or to the Kotlin reader. The Kotlin update and ending types have
// no public constructors, so an app (or this package's own tests) cannot build one to test its screen.
// `ChipReading.makeForTesting` drives a `ChipReading` with Swift values instead: scripted phases, and
// an ending from a `ChipReadOutcome`.

/// A handle for a scripted read: cancelling it ends the read as cancelled by the app.
private final class ScriptHandle: NSObject, ChipReadHandle, @unchecked Sendable {
    // Immutable after init.
    private let onCancel: @Sendable () -> Void
    init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
    var isEnded: Bool { false }
    func cancel() { onCancel() }
}

extension ChipReading {
    /// **A test aid, not for production.** A read that plays a script, so a screen or a model can be
    /// tested with no NFC and no chip.
    ///
    /// Each phase becomes one update, with progress that climbs evenly to `finalProgress`; then the
    /// read ends with `outcome`. With `delay` 0 everything is delivered before this returns; with a
    /// delay each update comes that many seconds after the last, and ``cancel()`` in between ends the
    /// read as `.cancelled(byPerson: false)`.
    ///
    /// The updates and the ending have no Kotlin object (`raw` is `nil`). The outcome is whatever
    /// you give: Swift can build `.cancelled`, `.notStarted(_)`, `.failed(_, access: nil)` (with a
    /// `NfcTagLost()`), `.keyRejected(ChipKeyCheckDigitMismatch(fields:))` and the like. A
    /// `.complete` or `.partial` needs a `ChipRead`, which Swift cannot build; pass one you have.
    ///
    /// ```swift
    /// let reading = ChipReading.makeForTesting(
    ///     phases: [.starting, .waitingForDocument(waited: 0), .readingFile(dataGroup: 1, bytesRead: 10, bytesTotal: 100)],
    ///     outcome: .cancelled(byPerson: true))
    /// ```
    public static func makeForTesting(
        phases: [ChipReadPhase],
        outcome: ChipReadOutcome,
        attempts: Int = 1,
        maxAttempts: Int = 3,
        finalProgress: ChipProgress = .zero,
        delay: TimeInterval = 0
    ) -> ChipReading {
        let count = max(phases.count, 1)
        let snapshots = phases.enumerated().map { index, phase in
            let fraction = finalProgress.fraction * Double(index + 1) / Double(count)
            return ChipReadSnapshot(
                phase: phase, progress: ChipProgress(fraction: fraction),
                attempt: attempts, maxAttempts: maxAttempts)
        }
        return makeForTesting(
            updates: snapshots,
            ending: ChipReadFinish(outcome: outcome, attempts: attempts, progress: finalProgress),
            delay: delay)
    }

    /// **A test aid, not for production.** As ``makeForTesting(phases:outcome:attempts:maxAttempts:finalProgress:delay:)``
    /// with the updates and the ending given whole.
    public static func makeForTesting(
        updates: [ChipReadSnapshot],
        ending: ChipReadFinish,
        delay: TimeInterval = 0
    ) -> ChipReading {
        let core = ChipReadingCore<ChipReadSnapshot, ChipReadFinish>()
        let last = updates.last?.progress ?? .zero
        let cancelled = ChipReadFinish(
            outcome: .cancelled(byPerson: false),
            attempts: updates.last?.attempt ?? 1, progress: last)
        core.attach(ScriptHandle { core.finish(cancelled) })
        if delay <= 0 {
            for update in updates { core.deliver(update) }
            core.finish(ending)
        } else {
            let nanos = UInt64(min(delay, 3600) * 1_000_000_000)
            Task {
                for update in updates {
                    try? await Task.sleep(nanoseconds: nanos)
                    core.deliver(update)
                }
                try? await Task.sleep(nanoseconds: nanos)
                core.finish(ending)
            }
        }
        return ChipReading(driving: core)
    }
}
