import Foundation
import Tessera

/// A running chip read, as Swift values: an `AsyncStream` of updates and one awaitable ending.
///
/// The Kotlin reader owns the whole NFC session: the system sheet, the radio, link loss and the file
/// reads. This type draws nothing. It turns the reader's callbacks into `async` Swift, so an app can
/// read a chip without linking the scanner screen. You never touch a Kotlin boxing type on the easy
/// path: updates and the ending are Swift values (``ChipReadSnapshot``, ``ChipReadFinish``).
///
/// The shortest use, three lines:
///
/// ```swift
/// let options = try ChipReadOptions.Builder(accessKey: key).build()
/// let reading = ChipReading.start(options: options)
/// let finish = await reading.ending
/// ```
///
/// A full use, with a scanned document as the key, root certificates from a file, a check time,
/// the texts on the system sheet, the settings and a progress bar:
///
/// ```swift
/// let key = try ChipAccessKey.from(parse: scanned)
/// let roots = TrustAnchors.shared.load(contentsOf: masterListURL)
/// let options = try ChipReadOptions.Builder(accessKey: key)
///     .dataGroups([1, 2])
///     .trustAnchors(roots)
///     .checkTime(Date())
///     .build()
/// let reading = ChipReading.start(
///     options: options,
///     texts: ChipReadTexts(text: { $0.phase == .connecting ? "Connecting" : nil }, ending: { _ in nil }),
///     settings: ChipReadSettings(linkLoss: .resume(2))
/// )
/// for await update in reading.updates { progress = update.fraction }
/// switch await reading.ending.outcome { ... }
/// ```
///
/// **The key is used up.** The entry point clears the access key inside `options` when the read
/// ends, whatever the ending. A second read needs a new key (and new options): build them again
/// from the document or the number. Check `key.isCleared` if you reuse options by mistake.
///
/// **One ending.** Every read ends once, after its last update. `ending` is safe to await from
/// several tasks, before or after the ending happened. `updates` finishes right after the ending.
///
/// **No update is lost.** Updates are buffered from the moment `start` returns, so a consumer that
/// starts its `for await` later still sees all of them, in order. The buffer has no limit: a slow
/// consumer never makes the reader wait and never misses a state change or the finish.
///
/// **Threads and order.** The Kotlin reader can deliver its calls on the main queue (its default) or
/// on its own thread (`CALLER`); with both, calls never overlap, come in order, and the ending comes
/// last. This package asks for its own thread (`CALLER`) in the settings it builds, because the
/// stream already does what the main queue would: the updates are queued in the order they arrive,
/// from one call at a time, and the ending is recorded after the last of them. Nothing hops queues
/// on the way, so nothing can reorder. A call may come before ``start(options:texts:settings:)``
/// returns; that is covered. The loop over `updates` runs on the actor of the task that runs it, so
/// in a `@MainActor` function you can update the UI directly. If you pass your own Kotlin settings
/// (``start(options:texts:coreSettings:)``) either `observerOn` value is safe.
///
/// **Sendable.** The Kotlin update and ending objects are not made `Sendable` (this package does
/// not add a conformance to types it does not own). ``ChipReadSnapshot`` and ``ChipReadFinish`` are
/// `@unchecked Sendable` instead: they wrap the Kotlin objects, which are `final` and read-only once
/// built.
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
    private let core: ChipReadingCore<ChipReadSnapshot, ChipReadFinish>

    /// The updates of the read, in order. Finishes right after the ending.
    ///
    /// Each read of this property returns the same stream, and a stream has one consumer: if two
    /// loops share it, each update goes to one of them. To watch from several places, loop once and
    /// forward the values, and use ``ending`` for the end.
    public let updates: AsyncStream<ChipReadSnapshot>

    /// Why a read cannot start on this device right now, or `nil` when it can. For example NFC is
    /// not supported (`.notSupported`) or the app lacks the entitlement. Ask before showing a "read
    /// the chip" button.
    public static var availability: NfcUnavailable.Reason? {
        CoreNfcChipRead.companion.availability()
    }

    /// Starts reading the chip. The system NFC sheet opens at once.
    ///
    /// The key inside `options` is cleared when the read ends: a new read needs a new key.
    ///
    /// - Parameters:
    ///   - options: What to read and how to open the chip. Build it with `ChipReadOptions.Builder`.
    ///   - texts: The words on the system sheet. `nil` uses the built-in English texts.
    ///     Use ``ChipReadTexts`` for your own.
    ///   - settings: How the read behaves around the radio. The default is
    ///     ``ChipReadSettings/init(linkLoss:settleDelay:commandTimeout:commandTimeoutBeforeAccess:waitAfterSystemEnd:telemetry:readTimeout:searchRestart:polling:)``
    ///     with no arguments.
    /// - Returns: The running read. A read that cannot start still returns: its ending says why.
    public static func start(
        options: ChipReadOptions,
        texts: (any CoreNfcSheetTexts)? = nil,
        settings: ChipReadSettings = ChipReadSettings()
    ) -> ChipReading {
        start(options: options, texts: texts, coreSettings: settings.kotlinSettings())
    }

    /// As ``start(options:texts:settings:)`` with Kotlin settings you built yourself.
    public static func start(
        options: ChipReadOptions,
        texts: (any CoreNfcSheetTexts)? = nil,
        coreSettings: CoreNfcReadSettings
    ) -> ChipReading {
        ChipReading { observer in
            CoreNfcChipRead.companion.start(
                options: options,
                observer: observer,
                texts: texts ?? CoreNfcDefaultSheetTexts.shared,
                settings: coreSettings
            )
        }
    }

    /// Builds a read from anything that starts one with an observer and returns its handle.
    /// Internal so the tests can start a fake.
    init(starter: (any ChipReadObserver) -> any ChipReadHandle) {
        let core = ChipReadingCore<ChipReadSnapshot, ChipReadFinish>()
        self.core = core
        self.updates = core.updates
        let observer = ChipReadObserverBridge(core)
        // Keep the observer until the ending, then let it go. Held before the start call, because a
        // read that cannot start may end before the call returns.
        core.retain(observer)
        core.attach(starter(observer))
    }

    /// Builds a read around a core that something other than Kotlin drives (the test aid).
    init(driving core: ChipReadingCore<ChipReadSnapshot, ChipReadFinish>) {
        self.core = core
        self.updates = core.updates
    }

    /// The one ending of the read. Waits until it happens, and returns at once if it already did.
    ///
    /// It holds the outcome, the attempts and the final progress; `await reading.ending.outcome` is
    /// the usual call. Safe to await from several tasks. Cancelling the awaiting task does not cancel
    /// the read and does not end the wait: use ``result()`` for that.
    public var ending: ChipReadFinish {
        get async { await core.awaitEnding() }
    }

    /// The one ending, like ``ending``, and the read is cancelled if the calling task is cancelled.
    ///
    /// This is the natural call in a SwiftUI `.task`: leaving the screen ends the task, and the task
    /// ends the read. After a cancel the outcome is `.cancelled(byPerson: false)`.
    public func result() async -> ChipReadFinish {
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

/// The Kotlin observer: converts each callback to a Swift value and hands it to the core. Its only
/// state is the core, which is `Sendable`, so no `unchecked` is needed. The core lets go of it at
/// the ending.
final class ChipReadObserverBridge: NSObject, ChipReadObserver, Sendable {
    private let core: ChipReadingCore<ChipReadSnapshot, ChipReadFinish>

    init(_ core: ChipReadingCore<ChipReadSnapshot, ChipReadFinish>) {
        self.core = core
    }

    func onUpdate(update: ChipReadUpdate) {
        core.deliver(ChipReadSnapshot(update))
    }

    func onEnding(ending: ChipReadEnding) {
        core.finish(ChipReadFinish(ending))
    }
}
