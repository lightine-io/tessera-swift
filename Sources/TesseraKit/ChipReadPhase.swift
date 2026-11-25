import Foundation
import Tessera

/// Where a chip read is, as a Swift `enum` you can `switch` over.
///
/// It mirrors `ChipReadState`, the Kotlin class hierarchy. The raw object stays reachable:
/// `snapshot.raw?.state`. The Kotlin type may gain members in a later release, so `switch` needs a
/// `default` or an `.unknown` case.
///
/// ```swift
/// switch snapshot.phase {
/// case .readingFile(let dataGroup, let bytesRead, let bytesTotal): ...
/// case .linkLost(let restartsLeft): ...
/// default: break
/// }
/// ```
///
/// - Since: 1.0.0
public enum ChipReadPhase: Sendable, Equatable {
    /// The reader waits for a document to come near the phone. `waited` is how long so far.
    case waitingForDocument(waited: TimeInterval)
    /// A document is near the phone.
    case documentFound
    /// The reader is connecting to the chip.
    case connecting
    /// The reader is opening access to the chip with the key.
    case openingAccess
    /// The reader is reading one file. `dataGroup` is its data group number, or `nil` for a file
    /// that is not a data group. `bytesTotal` is `nil` while the size is not known yet.
    case readingFile(dataGroup: Int?, bytesRead: Int, bytesTotal: Int?)
    /// The reader is checking the chip is genuine.
    case authenticatingChip
    /// The reader is checking the files it read.
    case checkingFiles
    /// The link to the chip was lost. The read tries again `restartsLeft` more times.
    case linkLost(restartsLeft: Int)
    /// The document was found, but the chip has not answered a command yet in this read, usually
    /// because the document is not in a good place. The read keeps trying, at no cost to the
    /// restarts. `tries` is how many commands went unanswered so far. A good line for a person:
    /// "Move the document slowly", then "Stay there" once the read goes on.
    case noAnswerYet(tries: Int)
    /// The read is starting.
    case starting
    /// The read is stopping.
    case stopping
    /// A state this version of `TesseraKit` does not know. Read the raw update for the object.
    case unknown

    // The value conversions, apart from the type switch, so a test can run them without a Kotlin
    // object (Swift cannot build the Kotlin states).
    static func waiting(waitedMillis: Int64) -> ChipReadPhase {
        .waitingForDocument(waited: TimeInterval(waitedMillis) / 1000)
    }

    static func reading(dataGroup: KotlinInt?, bytesRead: Int32, bytesTotal: KotlinInt?) -> ChipReadPhase {
        .readingFile(
            dataGroup: dataGroup.map { Int($0.int32Value) },
            bytesRead: Int(bytesRead),
            bytesTotal: bytesTotal.map { Int($0.int32Value) }
        )
    }

    static func lost(restartsLeft: Int32) -> ChipReadPhase { .linkLost(restartsLeft: Int(restartsLeft)) }

    static func noAnswer(tries: Int32) -> ChipReadPhase { .noAnswerYet(tries: Int(tries)) }

    /// Maps a raw object. It takes `Any` so a test can pass something that is not a state.
    static func from(_ object: Any) -> ChipReadPhase {
        switch object {
        case let state as ChipReadState.WaitingForDocument: return waiting(waitedMillis: state.waitedMillis)
        case is ChipReadState.DocumentFound: return .documentFound
        case is ChipReadState.Connecting: return .connecting
        case is ChipReadState.OpeningAccess: return .openingAccess
        case let state as ChipReadState.ReadingFile:
            return reading(dataGroup: state.file.dataGroup, bytesRead: state.bytesRead, bytesTotal: state.bytesTotal)
        case is ChipReadState.AuthenticatingChip: return .authenticatingChip
        case is ChipReadState.CheckingFiles: return .checkingFiles
        case let state as ChipReadState.NoAnswerYet: return noAnswer(tries: state.tries)
        case let state as ChipReadState.LinkLost: return lost(restartsLeft: state.restartsLeft)
        case is ChipReadState.Starting: return .starting
        case is ChipReadState.Stopping: return .stopping
        default: return .unknown
        }
    }
}

/// How far a read got, as plain Swift numbers.
///
/// `fraction` is an estimate that never goes back (see the Kotlin `ChipReadProgress`); it is 1 only
/// when the read is complete.
///
/// - Since: 1.0.0
public struct ChipProgress: @unchecked Sendable, Equatable {
    /// The share of the work done, 0 to 1. Never goes back.
    public let fraction: Double
    /// `fraction` in whole percent, rounded down: at most 99 until the read is complete.
    public let percent: Int
    /// How many application files this attempt has finished, read or not.
    public let filesDone: Int
    /// How many application files this attempt plans to read; `nil` until the file list is known.
    public let filesPlanned: Int?
    /// The Kotlin object this came from; `nil` for a scripted value. Kept to draw the built-in
    /// progress bar. A Kotlin `ChipReadProgress` is read-only after it is built, which is why this
    /// type is `@unchecked Sendable`.
    fileprivate let raw: ChipReadProgress?

    /// A progress from Swift values (a test, or a scripted read).
    public init(fraction: Double, percent: Int? = nil, filesDone: Int = 0, filesPlanned: Int? = nil) {
        let clamped = min(max(fraction.isNaN ? 0 : fraction, 0), 1)
        self.fraction = clamped
        self.percent = percent ?? Int(clamped * 100)
        self.filesDone = filesDone
        self.filesPlanned = filesPlanned
        self.raw = nil
    }

    init(_ progress: ChipReadProgress) {
        fraction = progress.fraction
        percent = Int(progress.percent)
        filesDone = Int(progress.filesDone)
        filesPlanned = progress.filesPlanned.map { Int($0.int32Value) }
        raw = progress
    }

    /// The Kotlin object, when this value came from the reader.
    var kotlin: ChipReadProgress? { raw }

    public static func == (lhs: ChipProgress, rhs: ChipProgress) -> Bool {
        lhs.fraction == rhs.fraction && lhs.percent == rhs.percent
            && lhs.filesDone == rhs.filesDone && lhs.filesPlanned == rhs.filesPlanned
    }

    /// No progress yet.
    public static let zero = ChipProgress(fraction: 0)
}

/// One update of a running read, as Swift values. The stream ``ChipReading/updates`` gives these.
///
/// - Since: 1.0.0
public struct ChipReadSnapshot: @unchecked Sendable {
    /// Where the read is.
    public let phase: ChipReadPhase
    /// How far it got.
    public let progress: ChipProgress
    /// The attempt this update belongs to, from 1.
    public let attempt: Int
    /// The most attempts the read may make.
    public let maxAttempts: Int
    /// The Kotlin update, for what the Swift values do not carry. `nil` for a scripted update.
    ///
    /// This type is `@unchecked Sendable` because of this property: a Kotlin update is a `final`
    /// object of read-only properties, built once and never written to by the SDK afterwards, so
    /// handing it to another task is safe. The Kotlin type itself is *not* declared `Sendable`:
    /// this package does not add a conformance to a type it does not own.
    public let raw: ChipReadUpdate?

    /// The progress as a fraction, 0 to 1.
    public var fraction: Double { progress.fraction }
    /// The progress in whole percent.
    public var percent: Int { progress.percent }

    /// A scripted update (a test, or a ``ChipReading/makeForTesting(phases:outcome:attempts:maxAttempts:finalProgress:delay:)`` read).
    public init(phase: ChipReadPhase, progress: ChipProgress = .zero, attempt: Int = 1, maxAttempts: Int = 3) {
        self.phase = phase
        self.progress = progress
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.raw = nil
    }

    init(_ update: ChipReadUpdate) {
        phase = update.state.phase
        progress = ChipProgress(update.progress)
        attempt = Int(update.attempt)
        maxAttempts = Int(update.maxAttempts)
        raw = update
    }
}

/// How a chip read ended, as a Swift `enum` you can `switch` over.
///
/// It mirrors `ChipReadEnding`, the Kotlin class hierarchy. Each case keeps the main object of
/// its Kotlin case. For the attempts and the final progress, use ``ChipReadFinish``, which wraps this.
/// It is not `Sendable`, because its payloads are Kotlin objects: ``ChipReadFinish`` carries it
/// across tasks, or switch over it where you got it.
/// The Kotlin type may gain members, so `switch` needs a `default` or an `.unknown` case.
///
/// - Since: 1.0.0
public enum ChipReadOutcome {
    /// Every file asked for was read.
    case complete(ChipRead)
    /// Some files were read, then something stopped the read. `stoppedIn` is where it was.
    case partial(ChipRead, stoppedBy: ChipError, stoppedIn: ChipReadPhase?)
    /// The read failed. `access` says how far the opening of the chip got, when it got that far.
    case failed(ChipError, access: AccessReport?)
    /// The chip did not accept the key.
    case keyNotAccepted(ChipAccessDenied)
    /// The key was refused before the read, with nothing sent to a chip: a check digit does not
    /// match (`ChipKeyCheckDigitMismatch`), or the key was already used by an earlier read
    /// (`ChipAccessDenied` with reason `KEY_CLEARED`; a new read needs a new key).
    case keyRejected(ChipError)
    /// The read was cancelled, by the person (`byPerson`) or by the app (`cancel()`).
    case cancelled(byPerson: Bool)
    /// The system ended the session. The error says why.
    case endedBySystem(NfcError)
    /// The read could not start. The reason says why, for example that NFC is not available.
    case notStarted(NfcUnavailable.Reason)
    /// An ending this version of `TesseraKit` does not know. Read ``ChipReadFinish/raw``.
    case unknown

    /// Maps a raw object. It takes `Any` so a test can pass something that is not an ending.
    static func from(_ object: Any) -> ChipReadOutcome {
        switch object {
        case let ending as ChipReadEnding.Complete: return .complete(ending.read)
        case let ending as ChipReadEnding.Partial:
            return .partial(ending.read, stoppedBy: ending.stoppedBy, stoppedIn: ending.stoppedIn.map { $0.phase })
        case let ending as ChipReadEnding.Failed: return .failed(ending.error, access: ending.access)
        case let ending as ChipReadEnding.KeyNotAccepted: return .keyNotAccepted(ending.error)
        case let ending as ChipReadEnding.KeyRejected: return .keyRejected(ending.error)
        case let ending as ChipReadEnding.Cancelled: return .cancelled(byPerson: ending.by == .person)
        case let ending as ChipReadEnding.EndedBySystem: return .endedBySystem(ending.reason)
        case let ending as ChipReadEnding.NotStarted: return .notStarted(ending.reason)
        default: return .unknown
        }
    }

    /// What was read, for `complete` and `partial`; `nil` otherwise.
    public var read: ChipRead? {
        switch self {
        case .complete(let read), .partial(let read, _, _): return read
        default: return nil
        }
    }

    /// The error behind the ending, when there is one: its `code` is stable, and
    /// ``Tessera/ChipError/statusWordInt`` is the chip's status word when it gave one.
    public var error: ChipError? {
        switch self {
        case .partial(_, let error, _): return error
        case .failed(let error, _): return error
        case .keyNotAccepted(let error): return error
        case .keyRejected(let error): return error
        case .endedBySystem(let error): return error
        default: return nil
        }
    }

    /// Whether the read ended because the chip never answered (``NfcNoAnswer``). Tell the person to
    /// try another position of the document on the phone.
    public var isNoAnswer: Bool { error?.isNoAnswer ?? false }
}

/// The ending of a read with everything the app needs in one value: the outcome, the number of
/// attempts and the final progress. ``ChipReading/ending`` gives this.
///
/// - Since: 1.0.0
public struct ChipReadFinish: @unchecked Sendable {
    /// How the read ended.
    public let outcome: ChipReadOutcome
    /// How many attempts the read made (a lost link and a new start make another).
    public let attempts: Int
    /// How far the read got when it ended.
    public let progress: ChipProgress
    /// The Kotlin ending; `nil` for a scripted one.
    ///
    /// `@unchecked Sendable`: the outcome holds Kotlin objects that are read-only once built (see
    /// ``ChipReadSnapshot/raw``); the Kotlin types are not made `Sendable` by this package.
    public let raw: ChipReadEnding?

    /// What was read, for a complete or partial read.
    public var read: ChipRead? { outcome.read }

    /// A scripted ending (a test, or a ``ChipReading/makeForTesting(phases:outcome:attempts:maxAttempts:finalProgress:delay:)`` read).
    public init(outcome: ChipReadOutcome, attempts: Int = 1, progress: ChipProgress = .zero) {
        self.outcome = outcome
        self.attempts = attempts
        self.progress = progress
        self.raw = nil
    }

    init(_ ending: ChipReadEnding) {
        outcome = ending.outcome
        attempts = Int(ending.attempts)
        progress = ChipProgress(ending.progress)
        raw = ending
    }
}

extension ChipReadState {
    /// This state as a Swift `enum`. The object itself is `self`.
    public var phase: ChipReadPhase { ChipReadPhase.from(self) }
}

extension ChipReadUpdate {
    /// The phase of this update's state, as a Swift `enum`. The raw object is `state`.
    public var phase: ChipReadPhase { state.phase }
}

extension ChipReadEnding {
    /// This ending as a Swift `enum`. The object itself is `self`.
    public var outcome: ChipReadOutcome { ChipReadOutcome.from(self) }
}

extension ChipReadProgress {
    /// The progress as a whole percent, 0 to 100, as an `Int`. (The Kotlin `percent` is an `Int32`
    /// and `fraction`, from 0 to 1, is already a `Double`.)
    public var percentInt: Int { Int(percent) }
}
