import Foundation
import Tessera

/// Where a chip read is, as a Swift `enum` you can `switch` over.
///
/// It mirrors `ChipReadState`, the Kotlin class hierarchy. The raw object stays reachable:
/// `update.state`. The Kotlin type may gain members in a later release, so `switch` needs a
/// `default` or an `.unknown` case.
///
/// ```swift
/// switch update.phase {
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
    /// The read is starting.
    case starting
    /// The read is stopping.
    case stopping
    /// A state this version of `TesseraKit` does not know. Read `update.state` for the raw object.
    case unknown

    /// Maps a raw object. It takes `Any` so a test can pass something that is not a state.
    static func from(_ object: Any) -> ChipReadPhase {
        switch object {
        case let state as ChipReadState.WaitingForDocument:
            return .waitingForDocument(waited: TimeInterval(state.waitedMillis) / 1000)
        case is ChipReadState.DocumentFound: return .documentFound
        case is ChipReadState.Connecting: return .connecting
        case is ChipReadState.OpeningAccess: return .openingAccess
        case let state as ChipReadState.ReadingFile:
            return .readingFile(
                dataGroup: state.file.dataGroup.map { Int($0.int32Value) },
                bytesRead: Int(state.bytesRead),
                bytesTotal: state.bytesTotal.map { Int($0.int32Value) }
            )
        case is ChipReadState.AuthenticatingChip: return .authenticatingChip
        case is ChipReadState.CheckingFiles: return .checkingFiles
        case let state as ChipReadState.LinkLost: return .linkLost(restartsLeft: Int(state.restartsLeft))
        case is ChipReadState.Starting: return .starting
        case is ChipReadState.Stopping: return .stopping
        default: return .unknown
        }
    }
}

/// How a chip read ended, as a Swift `enum` you can `switch` over.
///
/// It mirrors `ChipReadEnding`, the Kotlin class hierarchy. Each case keeps the main object of
/// its Kotlin case. The raw ending stays reachable and has more: `attempts` and `progress`.
/// It is not `Sendable`, because its payloads are Kotlin objects: switch over it where you got it.
/// The Kotlin type may gain members, so `switch` needs a `default` or an `.unknown` case.
///
/// - Since: 1.0.0
public enum ChipReadOutcome {
    /// Every file asked for was read.
    case complete(ChipRead)
    /// Some files were read, then something stopped the read. `stoppedIn` is where it was.
    case partial(ChipRead, stoppedBy: ChipError, stoppedIn: ChipReadState?)
    /// The read failed. `access` says how far the opening of the chip got, when it got that far.
    case failed(ChipError, access: AccessReport?)
    /// The chip did not accept the key.
    case keyNotAccepted(ChipAccessDenied)
    /// The key was refused before the read: a check digit does not match.
    case keyRejected(ChipKeyCheckDigitMismatch)
    /// The read was cancelled, by the person (`byPerson`) or by the app (`cancel()`).
    case cancelled(byPerson: Bool)
    /// The system ended the session. The error says why.
    case endedBySystem(NfcError)
    /// The read could not start. The reason says why, for example that NFC is not available.
    case notStarted(NfcUnavailable.Reason)
    /// An ending this version of `TesseraKit` does not know. Read the raw ending.
    case unknown

    /// Maps a raw object. It takes `Any` so a test can pass something that is not an ending.
    static func from(_ object: Any) -> ChipReadOutcome {
        switch object {
        case let ending as ChipReadEnding.Complete: return .complete(ending.read)
        case let ending as ChipReadEnding.Partial:
            return .partial(ending.read, stoppedBy: ending.stoppedBy, stoppedIn: ending.stoppedIn)
        case let ending as ChipReadEnding.Failed: return .failed(ending.error, access: ending.access)
        case let ending as ChipReadEnding.KeyNotAccepted: return .keyNotAccepted(ending.error)
        case let ending as ChipReadEnding.KeyRejected: return .keyRejected(ending.error)
        case let ending as ChipReadEnding.Cancelled: return .cancelled(byPerson: ending.by == .person)
        case let ending as ChipReadEnding.EndedBySystem: return .endedBySystem(ending.reason)
        case let ending as ChipReadEnding.NotStarted: return .notStarted(ending.reason)
        default: return .unknown
        }
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
