import Foundation
import TesseraCore

extension ChipError {
    /// The chip's status word as an `Int`, or `nil` when the error has none. (The Kotlin
    /// `statusWord` is a boxed `KotlinInt?`.) Never document data.
    ///
    /// The stable machine name of the error is the existing `code` (a `String`).
    public var statusWordInt: Int? { statusWord.map { Int($0.int32Value) } }

    /// Whether this is ``NfcNoAnswer``: the document was found, but the chip never got past the first
    /// commands. Tell the person to try another position of the document on the phone.
    public var isNoAnswer: Bool { self is NfcNoAnswer }
}

/// How one check came out, as a Swift `enum`. The reason is the stable `code` of the reason (a
/// module prefix and the reason in lower-case words, for example `chip.hash-differs`), or `nil` when
/// the Kotlin side gives none. The codes never change once released, so they are safe to log and to
/// use as keys of your own texts.
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
        case let failed as CheckOutcomeFailed: return .failed(reason: reasonCode(failed.reason))
        case let notRun as CheckOutcomeNotRun: return .notRun(reason: reasonCode(notRun.reason))
        case let notApplicable as CheckOutcomeNotApplicable: return .notApplicable(reason: reasonCode(notApplicable.reason))
        default: return .unknown
        }
    }

    private static func reasonCode(_ reason: (any CheckReason)?) -> String? { reason?.code }
}

extension ChipCheck {
    /// The stable name of the check. Same as `kind.code`.
    public var kindCode: String { kind.code }

    /// How the check came out, as a Swift `enum`. The Kotlin `outcome` is the raw object.
    public var result: ChipCheckResult { ChipCheckResult.from(outcome) }

    /// The per-field comparison, for the `Dg1MatchesPrintedMrz` check; `nil` for every other check
    /// and when the check did not run (no `printedDocument`, or no DG1).
    public var printedComparison: PrintedMrzComparison? { PrintedMrzComparison(detail) }
}

/// How one MRZ field of the chip's DG1 compares with the printed MRZ. A fact about the characters,
/// never a verdict on the document.
///
/// - Since: 1.0.0
public enum PrintedFieldMatch: String, Sendable, Equatable, CaseIterable {
    case same
    case different
    /// The two sides cannot be compared, for example a field the printed format does not have.
    case notComparable
    /// A result this version does not know.
    case unknown

    init(_ match: ChipFieldMatch) {
        switch match {
        case .same: self = .same
        case .different: self = .different
        case .notComparable: self = .notComparable
        default: self = .unknown
        }
    }
}

/// One field of the printed-MRZ comparison: its name and how it came out. No values.
///
/// - Since: 1.0.0
public struct PrintedFieldComparison: Sendable, Equatable {
    /// The field that was compared.
    public let field: ChipKeyField
    /// How the field came out: `same`, `different` or `notComparable`.
    public let match: PrintedFieldMatch

    /// Creates the comparison of one field.
    public init(field: ChipKeyField, match: PrintedFieldMatch) {
        self.field = field
        self.match = match
    }
}

/// The `Dg1MatchesPrintedMrz` check as Swift values: for each field, `same`, `different` or
/// `notComparable`, and whether the two MRZs have the same format. Never a value of the document.
///
/// Ask for it with `ChipReadOptions.Builder.printedDocument(_:)`, then read it from the check:
/// `read.checks.compactMap(\.printedComparison).first`.
///
/// - Since: 1.0.0
public struct PrintedMrzComparison: Sendable, Equatable {
    /// `true` when both MRZs have the same format (for example both TD3).
    public let sameFormat: Bool
    /// Every field the comparison covers, in the order of ``ChipKeyField/allCases``.
    public let fields: [PrintedFieldComparison]

    /// The fields that came out `different`.
    public var differingFields: [ChipKeyField] { fields.filter { $0.match == .different }.map(\.field) }
    /// `true` when the format is the same and no field is `different` or `notComparable`.
    public var allSame: Bool { sameFormat && fields.allSatisfy { $0.match == .same } }

    /// Creates the comparison from the format result and the per-field results.
    public init(sameFormat: Bool, fields: [PrintedFieldComparison]) {
        self.sameFormat = sameFormat
        self.fields = fields
    }

    /// The Swift view of the check's detail; `nil` for a detail of another kind.
    public init?(_ detail: ChipCheckDetail?) {
        guard let printed = detail as? ChipCheckDetail.PrintedMrzFields else { return nil }
        let byField = Dictionary(
            printed.fields.map { (ChipKeyField($0.key), PrintedFieldMatch($0.value)) },
            uniquingKeysWith: { first, _ in first })
        self.init(
            sameFormat: printed.sameFormat,
            fields: ChipKeyField.allCases.compactMap { field in
                byField[field].map { PrintedFieldComparison(field: field, match: $0) }
            })
    }
}
