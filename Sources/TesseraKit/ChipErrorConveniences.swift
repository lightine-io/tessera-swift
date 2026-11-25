import Foundation
import Tessera

extension ChipError {
    /// The chip's status word as an `Int`, or `nil` when the error has none. (The Kotlin
    /// `statusWord` is a boxed `KotlinInt?`.) Never document data.
    ///
    /// The stable machine name of the error is the existing `code` (a `String`).
    public var statusWordInt: Int? { statusWord.map { Int($0.int32Value) } }
}

/// How one check came out, as a Swift `enum`. The reason is the stable Kotlin name of the reason
/// (`HASH_DIFFERS`, `NO_TIME_GIVEN`, ...), or `nil` when the Kotlin side gives none.
///
/// - Since: 1.0.0
public enum ChipCheckResult: Sendable, Equatable {
    case passed
    case failed(reason: String?)
    case notRun(reason: String?)
    case notApplicable(reason: String?)
    /// An outcome this version does not know.
    case unknown

    /// The Swift view of any Kotlin check outcome: a chip check's, a master list check's or an MRZ
    /// comparison's.
    public init(_ outcome: any CheckOutcome) { self = Self.from(outcome) }

    static func from(_ outcome: any CheckOutcome) -> ChipCheckResult {
        switch outcome {
        case is CheckOutcomePassed: return .passed
        case let failed as CheckOutcomeFailed: return .failed(reason: reasonName(failed.reason))
        case let notRun as CheckOutcomeNotRun: return .notRun(reason: reasonName(notRun.reason))
        case let notApplicable as CheckOutcomeNotApplicable: return .notApplicable(reason: reasonName(notApplicable.reason))
        default: return .unknown
        }
    }

    // `CheckReason` is a marker protocol with no `code`; its implementations are Kotlin enums, whose
    // `name` is stable. A reason of another shape has no name here.
    private static func reasonName(_ reason: (any CheckReason)?) -> String? {
        (reason as? KotlinEnum<AnyObject>)?.name
    }
}

extension ChipCheck {
    /// The stable name of the check. Same as `kind.code`.
    public var kindCode: String { kind.code }

    /// How the check came out, as a Swift `enum`. The Kotlin `outcome` is the raw object.
    public var result: ChipCheckResult { ChipCheckResult.from(outcome) }
}
