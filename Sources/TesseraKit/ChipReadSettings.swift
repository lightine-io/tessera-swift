import Foundation
import Tessera

/// What a read does when the link to the chip is lost, usually because the document moved.
/// Mirrors `LinkLossPolicy`.
///
/// For an ordinary app keep ``resume(_:)`` with 2 restarts, the default. The number of restarts is
/// 1 to 3; ``ChipReadSettings`` clamps a value outside that range.
///
/// - Since: 1.0.0
public enum LinkLoss: Sendable, Equatable {
    /// End the read at the first lost link.
    case end
    /// Start the read again from the beginning, at most this many times.
    case readAgain(Int)
    /// Wait for the document in the same system session and go on from where it stopped, at most
    /// this many times.
    case resume(Int)

    /// The restarts the Kotlin policy allows: 1 to 3.
    public static let restartRange = 1...3

    /// The same policy with its restarts inside ``restartRange``.
    public var clamped: LinkLoss {
        switch self {
        case .end: return .end
        case .readAgain(let count): return .readAgain(Self.clamp(count))
        case .resume(let count): return .resume(Self.clamp(count))
        }
    }

    private static func clamp(_ count: Int) -> Int { min(max(count, restartRange.lowerBound), restartRange.upperBound) }

    /// The Kotlin policy, with the restarts clamped so it cannot be refused.
    func kotlinPolicy() -> LinkLossPolicy {
        let companion = LinkLossPolicy.companion
        switch clamped {
        case .end: return companion.end()
        case .readAgain(let count): return (try? companion.readAgain(maxRestarts: Int32(count))) ?? companion.end()
        case .resume(let count): return (try? companion.resume(maxRestarts: Int32(count))) ?? companion.end()
        }
    }

    init(kotlin policy: LinkLossPolicy) {
        switch policy {
        case is LinkLossPolicy.ReadAgain: self = .readAgain(Int(policy.maxRestarts))
        case is LinkLossPolicy.Resume: self = .resume(Int(policy.maxRestarts))
        default: self = .end
        }
    }
}

/// What the system session polls for. Mirrors `CoreNfcPolling`.
///
/// From iOS 26.4 Core NFC can poll for ISO 14443 tags and PACE tags (chips that answer only after
/// PACE polling) together; before iOS 26.4 it cannot combine them, so ISO 14443 is polled alone.
///
/// - Since: 1.0.0
public enum ChipReadPolling: Sendable, Equatable, CaseIterable {
    /// The SDK's choice, the default: today the same as ``iso14443AndPace``.
    case automatic
    /// ISO 14443 polling only, on every iOS version, with the session opened as before iOS 26.4 (the
    /// select identifiers come from the app's Info.plist). Misses chips that answer only after PACE
    /// polling.
    case iso14443
    /// ISO 14443 and PACE polling together from iOS 26.4; ISO 14443 alone before, where the system
    /// cannot combine them.
    case iso14443AndPace

    /// The Kotlin choice.
    func kotlinPolling() -> CoreNfcPolling {
        switch self {
        case .automatic: return .automatic
        case .iso14443: return .iso14443
        case .iso14443AndPace: return .iso14443AndPace
        }
    }

    init(kotlin polling: CoreNfcPolling) {
        switch polling {
        case .iso14443: self = .iso14443
        case .iso14443AndPace: self = .iso14443AndPace
        default: self = .automatic
        }
    }
}

/// How a read behaves around the radio, with a default for every value: `ChipReadSettings()` suits
/// an ordinary app, and `ChipReadSettings(linkLoss: .end)` changes one value only.
///
/// **Invalid values are clamped, never refused,** so building settings cannot fail:
/// - the restarts of ``LinkLoss`` go to 1 to 3;
/// - `settleDelay` and `waitAfterSystemEnd` below 0 (or not a number) become 0;
/// - `commandTimeout`, `readTimeout` and `commandTimeoutBeforeAccess` below one millisecond (or not a
///   number) become one millisecond, and one above a day becomes a day;
/// - `searchRestart` of `nil` or 0 is off; any other value below 2 seconds (or not a number) becomes
///   2 seconds, and one above a day becomes a day;
/// - `maxSessionRenewals` below 0 becomes 0 (off);
/// - `sessionRenew` of `nil` or 0 is off; any other value below 5 seconds (or not a number) becomes
///   5 seconds, and one above a day becomes a day;
/// - `busyRetry` of `nil`, 0, below 0 or not a number is off; one above a day becomes a day;
/// - `tagTimeLimit` of `nil` or 0 is off; any other value below 10 seconds (or not a number) becomes
///   10 seconds, and one above 60 seconds becomes 60 seconds.
///
/// Read ``normalized`` to see the values that will be used. Times are in seconds and are rounded to
/// whole milliseconds for the reader.
///
/// - Since: 1.0.0
public struct ChipReadSettings {
    /// What the read does when the link to the chip is lost. Default: resume, at most 2 times.
    public var linkLoss: LinkLoss
    /// How long the read waits after the system finds a document before the first command, so the
    /// hand can settle. Default 0.4 seconds.
    public var settleDelay: TimeInterval
    /// The longest wait for the chip's answer to one command that makes the chip do heavy
    /// cryptographic work (the key steps of BAC and PACE, chip and active authentication, and any
    /// extended-length command); a longer wait counts as a lost link. Default 5 seconds. It is the
    /// longest of the three limits: a longer ``readTimeout`` or ``commandTimeoutBeforeAccess`` is cut to it.
    public var commandTimeout: TimeInterval
    /// The longest wait for the chip's answer to one ordinary command after access (selecting and
    /// reading a file); a longer wait counts as a lost link. Default 2 seconds. A slow but legal chip
    /// may need more: raise it then.
    public var readTimeout: TimeInterval
    /// The longest wait for the chip's answer to one command before access: the plain commands before
    /// the key is used. They answer in milliseconds, so a chip that gets too little power is noticed
    /// sooner. An unanswered command is a try that costs no restart (``ChipReadPhase/noAnswerYet(tries:)``).
    /// Default 1.5 seconds. From the first command that uses the key, ``commandTimeout`` applies; when
    /// this value is longer, ``commandTimeout`` applies before access too.
    public var commandTimeoutBeforeAccess: TimeInterval
    /// How long a new read waits before it begins a system session when the previous one was ended
    /// by the system or refused because the reader was busy. Default 1 second.
    public var waitAfterSystemEnd: TimeInterval
    /// How often the read asks the system to search for the document again while it waits for one and
    /// the system has reported none. A new search gives a weak first contact another try with the
    /// sheet still up. Default 4 seconds. `nil` (or 0) turns it off; any other value is at least
    /// 2 seconds.
    public var searchRestart: TimeInterval?
    /// How many times one read may close its system session and open a new one while no document was
    /// reported (see ``ChipReadPhase/renewingSession(renewal:)``): after the system's own end with
    /// code 202, or after ``sessionRenew`` passed. The system sheet closes and opens again. Default 1.
    /// 0 turns renewals off. A value below 0 becomes 0.
    public var maxSessionRenewals: Int
    /// How long a system session may go with no document reported before the read opens a new one,
    /// while ``maxSessionRenewals`` allows. Default `nil`: off. The renewal after the system's code 202
    /// still happens. Any other value is at least 5 seconds; 0 is also off.
    public var sessionRenew: TimeInterval?
    /// How long the read keeps trying to begin a system session that the system refuses as busy.
    /// Default 6 seconds. `nil` (or 0) turns the tries off.
    public var busyRetry: TimeInterval?
    /// How long the read uses one connection to the document before it restarts the search on purpose,
    /// before the system's own limit of about 20 seconds on one connection, and goes on from the same
    /// byte. Nothing new is shown to the app. Default 18 seconds. `nil` (or 0) turns it off; any other
    /// value is from 10 to 60 seconds.
    public var tagTimeLimit: TimeInterval?
    /// Where the read's step events go (see ``ChipReadStepSink``); `nil` uses the sink registered in
    /// `TelemetrySinkRegistry`, which drops everything when none is registered.
    public var telemetry: (any TelemetrySink)?
    /// What the system session polls for. Default ``ChipReadPolling/automatic``.
    public var polling: ChipReadPolling

    public init(
        linkLoss: LinkLoss = .resume(2),
        settleDelay: TimeInterval = 0.4,
        commandTimeout: TimeInterval = 5,
        commandTimeoutBeforeAccess: TimeInterval = 1.5,
        waitAfterSystemEnd: TimeInterval = 1,
        telemetry: (any TelemetrySink)? = nil,
        readTimeout: TimeInterval = 2,
        searchRestart: TimeInterval? = 4,
        polling: ChipReadPolling = .automatic,
        maxSessionRenewals: Int = 1,
        sessionRenew: TimeInterval? = nil,
        busyRetry: TimeInterval? = 6,
        tagTimeLimit: TimeInterval? = 18
    ) {
        self.linkLoss = linkLoss
        self.settleDelay = settleDelay
        self.commandTimeout = commandTimeout
        self.commandTimeoutBeforeAccess = commandTimeoutBeforeAccess
        self.waitAfterSystemEnd = waitAfterSystemEnd
        self.telemetry = telemetry
        self.readTimeout = readTimeout
        self.searchRestart = searchRestart
        self.polling = polling
        self.maxSessionRenewals = maxSessionRenewals
        self.sessionRenew = sessionRenew
        self.busyRetry = busyRetry
        self.tagTimeLimit = tagTimeLimit
    }

    /// The Kotlin `searchRestartMillis`: 0 for off, otherwise 2000 or more.
    private static func searchRestartMillis(_ seconds: TimeInterval?) -> Int64 {
        guard let seconds, seconds != 0 else { return 0 }
        return millis(seconds, minimum: 2_000)
    }

    /// The Kotlin `sessionRenewMillis`: 0 for off, otherwise 5000 or more.
    private static func sessionRenewMillis(_ seconds: TimeInterval?) -> Int64 {
        guard let seconds, seconds != 0 else { return 0 }
        return millis(seconds, minimum: 5_000)
    }

    /// The Kotlin `tagTimeLimitMillis`: 0 for off, otherwise 10000 to 60000.
    private static func tagTimeLimitMillis(_ seconds: TimeInterval?) -> Int64 {
        guard let seconds, seconds != 0 else { return 0 }
        return min(millis(seconds, minimum: 10_000), 60_000)
    }

    /// The Kotlin `busyRetryMillis`: 0 for off (also for a negative or missing number), otherwise at
    /// least 1.
    private static func busyRetryMillis(_ seconds: TimeInterval?) -> Int64 {
        guard let seconds, !seconds.isNaN, seconds > 0 else { return 0 }
        return millis(seconds, minimum: 1)
    }

    /// The Kotlin `maxSessionRenewals`: 0 or more, and it fits an `Int32`.
    private static func renewalCount(_ count: Int) -> Int32 { Int32(clamping: max(count, 0)) }

    private static let maxMillis: Int64 = 86_400_000

    private static func millis(_ seconds: TimeInterval, minimum: Int64) -> Int64 {
        if seconds.isNaN { return minimum }
        let value = (seconds * 1000).rounded()
        if value >= Double(maxMillis) { return maxMillis } // also infinity
        if value <= Double(minimum) { return minimum }
        return Int64(value)
    }

    /// These settings with every value inside the range the reader accepts.
    public var normalized: ChipReadSettings {
        ChipReadSettings(
            linkLoss: linkLoss.clamped,
            settleDelay: TimeInterval(Self.millis(settleDelay, minimum: 0)) / 1000,
            commandTimeout: TimeInterval(Self.millis(commandTimeout, minimum: 1)) / 1000,
            commandTimeoutBeforeAccess: TimeInterval(Self.millis(commandTimeoutBeforeAccess, minimum: 1)) / 1000,
            waitAfterSystemEnd: TimeInterval(Self.millis(waitAfterSystemEnd, minimum: 0)) / 1000,
            telemetry: telemetry,
            readTimeout: TimeInterval(Self.millis(readTimeout, minimum: 1)) / 1000,
            searchRestart: searchRestart.flatMap { $0 == 0 ? nil : TimeInterval(Self.searchRestartMillis($0)) / 1000 },
            polling: polling,
            maxSessionRenewals: Int(Self.renewalCount(maxSessionRenewals)),
            sessionRenew: sessionRenew.flatMap { $0 == 0 ? nil : TimeInterval(Self.sessionRenewMillis($0)) / 1000 },
            busyRetry: Self.busyRetryMillis(busyRetry) == 0 ? nil : TimeInterval(Self.busyRetryMillis(busyRetry)) / 1000,
            tagTimeLimit: Self.tagTimeLimitMillis(tagTimeLimit) == 0 ? nil : TimeInterval(Self.tagTimeLimitMillis(tagTimeLimit)) / 1000
        )
    }

    /// The Kotlin settings these values stand for (clamped as described above). The observer thread is
    /// `CALLER`: updates reach ``ChipReading`` on the reader's own thread, in order and never
    /// overlapping, and ``ChipReading/updates`` hands them on from there.
    public func kotlinSettings() -> CoreNfcReadSettings {
        let builder = CoreNfcReadSettings.Builder()
            .linkLoss(policy: linkLoss.kotlinPolicy())
            .settleDelayMillis(millis: Self.millis(settleDelay, minimum: 0))
            .commandTimeoutMillis(millis: Self.millis(commandTimeout, minimum: 1))
            .commandTimeoutBeforeAccessMillis(millis: Self.millis(commandTimeoutBeforeAccess, minimum: 1))
            .readTimeoutMillis(millis: Self.millis(readTimeout, minimum: 1))
            .searchRestartMillis(millis: Self.searchRestartMillis(searchRestart))
            .waitAfterSystemEndMillis(millis: Self.millis(waitAfterSystemEnd, minimum: 0))
            .telemetry(sink: telemetry)
            .polling(choice: polling.kotlinPolling())
            .maxSessionRenewals(count: Self.renewalCount(maxSessionRenewals))
            .sessionRenewMillis(millis: Self.sessionRenewMillis(sessionRenew))
            .busyRetryMillis(millis: Self.busyRetryMillis(busyRetry))
            .tagTimeLimitMillis(millis: Self.tagTimeLimitMillis(tagTimeLimit))
            // The Swift layer orders and buffers updates itself (see `ChipReadingCore`), so the
            // reader's own thread is enough: asking for the main queue would add one more hop.
            .observerOn(thread: .caller)
        // Every value is in range, so the build cannot be refused; the defaults are the fallback.
        return (try? builder.build()) ?? CoreNfcReadSettings()
    }

    /// The Swift view of Kotlin settings.
    public init(_ settings: CoreNfcReadSettings) {
        self.init(
            linkLoss: LinkLoss(kotlin: settings.linkLoss),
            settleDelay: TimeInterval(settings.settleDelayMillis) / 1000,
            commandTimeout: TimeInterval(settings.commandTimeoutMillis) / 1000,
            commandTimeoutBeforeAccess: TimeInterval(settings.commandTimeoutBeforeAccessMillis) / 1000,
            waitAfterSystemEnd: TimeInterval(settings.waitAfterSystemEndMillis) / 1000,
            telemetry: settings.telemetry,
            readTimeout: TimeInterval(settings.readTimeoutMillis) / 1000,
            searchRestart: settings.searchRestartMillis == 0 ? nil : TimeInterval(settings.searchRestartMillis) / 1000,
            polling: ChipReadPolling(kotlin: settings.polling),
            maxSessionRenewals: Int(settings.maxSessionRenewals),
            sessionRenew: settings.sessionRenewMillis == 0 ? nil : TimeInterval(settings.sessionRenewMillis) / 1000,
            busyRetry: settings.busyRetryMillis == 0 ? nil : TimeInterval(settings.busyRetryMillis) / 1000,
            tagTimeLimit: settings.tagTimeLimitMillis == 0 ? nil : TimeInterval(settings.tagTimeLimitMillis) / 1000
        )
    }
}

/// How one step of a read went. Mirrors `ChipReadStepOutcome`.
///
/// - Since: 1.0.0
public enum ChipReadStepResult: String, Sendable, Equatable {
    case succeeded, failed, skipped, unknown
}

/// One step event of a read, as Swift values. It never holds document or chip data.
///
/// - Since: 1.0.0
public struct ChipReadStepEvent: Sendable, Equatable {
    /// The step, as the Kotlin name of `ChipReadStep` (`READ_FILE`, `PACE`, `BAC`, ...). A string, so a
    /// step added later still comes through.
    public let step: String
    public let outcome: ChipReadStepResult
    /// The access protocol, for the steps that have one.
    public let `protocol`: String?
    /// The file id, for a file read.
    public let fileId: Int?
    /// How many bytes the step moved, when it counts them.
    public let byteCount: Int?
    /// The chip's status word, when it answered with one.
    public let statusWord: Int?
    public let durationMillis: Int64
    /// The platform's own code, for a step that ended on one: the `SESSION_END` step, with Core NFC's
    /// `NFCReaderError` code, and the `SESSION_RENEW` step, with 202 when the system's end led to the
    /// renewal. `nil` for every other step, and for a renewal after the time passed.
    public let systemCode: Int?
    /// The number of the new system session, from 1, for the `SESSION_RENEW` step; `nil` for every
    /// other step.
    public let renewal: Int?

    public init(
        step: String, outcome: ChipReadStepResult, protocol: String? = nil, fileId: Int? = nil,
        byteCount: Int? = nil, statusWord: Int? = nil, durationMillis: Int64 = 0, systemCode: Int? = nil,
        renewal: Int? = nil
    ) {
        self.step = step
        self.outcome = outcome
        self.protocol = `protocol`
        self.fileId = fileId
        self.byteCount = byteCount
        self.statusWord = statusWord
        self.durationMillis = durationMillis
        self.systemCode = systemCode
        self.renewal = renewal
    }

    init(_ event: ChipReadEvent) {
        step = event.step.name
        switch event.outcome {
        case .succeeded: outcome = .succeeded
        case .failed: outcome = .failed
        case .skipped: outcome = .skipped
        default: outcome = .unknown
        }
        `protocol` = event.protocol
        fileId = event.fileId.map { Int($0.int32Value) }
        byteCount = event.byteCount.map { Int($0.int32Value) }
        statusWord = event.statusWord.map { Int($0.int32Value) }
        durationMillis = event.durationMillis
        systemCode = event.systemCode.map { Int($0.int32Value) }
        renewal = event.renewal.map { Int($0.int32Value) }
    }
}

/// A telemetry sink that gives each read step to a Swift closure. Put it in
/// ``ChipReadSettings/telemetry`` to follow the per-step timeline of a read:
///
/// ```swift
/// let sink = ChipReadStepSink { event in print(event.step, event.outcome, event.durationMillis) }
/// ChipReading.start(options: options, settings: ChipReadSettings(telemetry: sink))
/// ```
///
/// The closure runs on the reader's background queue. Events that are not read steps are ignored.
///
/// This class stays a `TelemetrySink` that filters for `ChipReadEvent` itself. The Kotlin
/// `ChipReadEventSink` is the same filter as a protocol, but a Swift type that adopts it must still
/// write `record(event:)` for the general sink, so adopting it would not make this class shorter.
///
/// - Since: 1.0.0
public final class ChipReadStepSink: NSObject, TelemetrySink, @unchecked Sendable {
    // Immutable, and the closure is `@Sendable`: nothing here changes after init.
    private let handler: @Sendable (ChipReadStepEvent) -> Void

    public init(_ handler: @escaping @Sendable (ChipReadStepEvent) -> Void) {
        self.handler = handler
    }

    public func record(event: any TelemetryEvent) {
        guard let step = event as? ChipReadEvent else { return }
        handler(ChipReadStepEvent(step))
    }
}
