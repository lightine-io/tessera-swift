import Foundation
import Tessera

// The Kotlin update and ending are immutable objects: `final` classes of read-only properties, built
// once on the reader's queue and never touched by the SDK afterwards. Kotlin cannot mark them
// `Sendable`, so this file does, once, here. `@retroactive` because the types come from the `Tessera`
// binary. Why it is safe to hand them to any task: the SDK keeps no reference it writes through, and
// the one mutable thing inside a finished read, the byte arrays of its files, is the consumer's copy.
extension ChipReadUpdate: @retroactive @unchecked Sendable {}
extension ChipReadEnding: @retroactive @unchecked Sendable {}

/// A running chip read, as Swift values: an `AsyncStream` of updates and one awaitable ending.
///
/// The Kotlin reader owns the whole NFC session: the system sheet, the radio, link loss and the file
/// reads. This type draws nothing. It turns the reader's callbacks into `async` Swift, so an app can
/// read a chip without linking the scanner screen.
///
/// The shortest use, three lines:
///
/// ```swift
/// let options = try ChipReadOptions.Builder(accessKey: key).build()
/// let reading = ChipReading.start(options: options)
/// let ending = await reading.ending
/// ```
///
/// A full use, with the texts on the system sheet, the settings and a progress bar:
///
/// ```swift
/// let options = try ChipReadOptions.Builder(accessKey: key)
///     .dataGroups(numbers: [1, 2])
///     .build()
/// let reading = ChipReading.start(
///     options: options,
///     texts: myTexts,        // a CoreNfcSheetTexts, or nil for the built-in English texts
///     settings: mySettings   // a CoreNfcReadSettings, or nil for the defaults
/// )
/// for await update in reading.updates {
///     progress = update.progress.fraction
/// }
/// switch await reading.ending.outcome {
/// case .complete(let read): show(read)
/// default: showFailure()
/// }
/// ```
///
/// **One ending.** Every read ends once, after its last update. `ending` is safe to await from
/// several tasks, before or after the ending happened. `updates` finishes right after the ending.
///
/// **No update is lost.** Updates are buffered from the moment `start` returns, so a consumer that
/// starts its `for await` later still sees all of them, in order. The buffer has no limit: a slow
/// consumer never makes the reader wait and never misses a state change or the finish.
///
/// **Threads.** The reader calls back on a background queue. The loop over `updates` runs on the
/// actor of the task that runs it, so in a `@MainActor` function you can update the UI directly.
///
/// **Cancelling.** Cancelling the Swift `Task` that iterates `updates` or awaits `ending` does not
/// cancel the read: that loop ends for that consumer only, and the read goes on. Call ``cancel()``,
/// or await ``result()``, which cancels the read when its task is cancelled. To tie one loop to the
/// read yourself:
///
/// ```swift
/// await withTaskCancellationHandler {
///     for await update in reading.updates { show(update) }
/// } onCancel: {
///     reading.cancel()
/// }
/// ```
///
/// Dropping the last reference to a `ChipReading` does not cancel the read either. The read ends
/// only through its ending, so keep the value or call ``cancel()``.
///
/// - Since: 1.0.0
public final class ChipReading: Sendable {
    private let core: ChipReadingCore<ChipReadUpdate, ChipReadEnding>

    /// The updates of the read, in order. Finishes right after the ending.
    ///
    /// Each read of this property returns the same stream, and a stream has one consumer: if two
    /// loops share it, each update goes to one of them. To watch from several places, loop once and
    /// forward the values, and use ``ending`` for the end.
    public let updates: AsyncStream<ChipReadUpdate>

    /// Starts reading the chip. The system NFC sheet opens at once.
    ///
    /// - Parameters:
    ///   - options: What to read and how to open the chip. Build it with `ChipReadOptions.Builder`.
    ///   - texts: The words on the system sheet. `nil` uses the built-in English texts.
    ///   - settings: How the read behaves around the radio. `nil` uses the defaults.
    /// - Returns: The running read. A read that cannot start still returns: its ending says why.
    public static func start(
        options: ChipReadOptions,
        texts: (any CoreNfcSheetTexts)? = nil,
        settings: CoreNfcReadSettings? = nil
    ) -> ChipReading {
        ChipReading { observer in
            let companion = CoreNfcChipRead.companion
            switch (texts, settings) {
            case (nil, nil):
                return companion.start(options: options, observer: observer)
            case (let texts?, nil):
                return companion.start(options: options, texts: texts, observer: observer)
            case (let texts, let settings?):
                return companion.start(
                    options: options,
                    texts: texts ?? CoreNfcDefaultSheetTexts.shared,
                    settings: settings,
                    observer: observer
                )
            }
        }
    }

    /// Builds a read from anything that starts one with an observer and returns its handle.
    /// Internal so the tests can start a fake.
    init(starter: (any ChipReadObserver) -> any ChipReadHandle) {
        let core = ChipReadingCore<ChipReadUpdate, ChipReadEnding>()
        self.core = core
        self.updates = core.updates
        let observer = ChipReadObserverBridge(core)
        // Keep the observer until the ending, then let it go. Held before the start call, because a
        // read that cannot start may end before the call returns.
        core.retain(observer)
        core.attach(starter(observer))
    }

    /// The one ending of the read. Waits until it happens, and returns at once if it already did.
    ///
    /// Safe to await from several tasks. Cancelling the awaiting task does not cancel the read and
    /// does not end the wait: use ``result()`` for that.
    public var ending: ChipReadEnding {
        get async { await core.awaitEnding() }
    }

    /// The one ending, like ``ending``, and the read is cancelled if the calling task is cancelled.
    ///
    /// This is the natural call in a SwiftUI `.task`: leaving the screen ends the task, and the task
    /// ends the read. After a cancel the ending is `ChipReadEnding.Cancelled`.
    public func result() async -> ChipReadEnding {
        await withTaskCancellationHandler {
            await core.awaitEnding()
        } onCancel: {
            core.cancel()
        }
    }

    /// Asks the read to stop. The ending then says it was cancelled by the app.
    ///
    /// Safe to call more than once, from any thread, and after the read ended: the reader gets one
    /// request, and later calls do nothing.
    public func cancel() {
        core.cancel()
    }
}

/// The Kotlin observer: hands each callback to the core. Its only state is the core, which is
/// `Sendable`, so no `unchecked` is needed. The core lets go of it at the ending.
final class ChipReadObserverBridge: NSObject, ChipReadObserver, Sendable {
    private let core: ChipReadingCore<ChipReadUpdate, ChipReadEnding>

    init(_ core: ChipReadingCore<ChipReadUpdate, ChipReadEnding>) {
        self.core = core
    }

    func onUpdate(update: ChipReadUpdate) {
        core.deliver(update)
    }

    func onEnding(ending: ChipReadEnding) {
        core.finish(ending)
    }
}
