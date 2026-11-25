import Foundation
import TesseraCore

/// An MRZ field, by name: the one a key could not be made from, one the typed-field normaliser
/// changed, or one the printed-MRZ comparison speaks about. Mirrors `MrzField`; a field this version
/// does not know is `.unknown`.
///
/// - Since: 1.0.0
public enum ChipKeyField: String, Sendable, Equatable, CaseIterable {
    case documentType, issuingState, nameField, documentNumber, nationality
    case dateOfBirth, dateOfExpiry, optionalData, composite, sex
    case unknown

    init(_ field: MrzField) {
        switch field {
        case .documentType: self = .documentType
        case .issuingState: self = .issuingState
        case .nameField: self = .nameField
        case .documentNumber: self = .documentNumber
        case .nationality: self = .nationality
        case .dateOfBirth: self = .dateOfBirth
        case .dateOfExpiry: self = .dateOfExpiry
        case .optionalData: self = .optionalData
        case .composite: self = .composite
        case .sex: self = .sex
        default: self = .unknown
        }
    }
}

/// Why no chip access key could be made from the MRZ. Mirrors `MrzKeyProblem`.
///
/// - Since: 1.0.0
public enum ChipKeyProblem: String, Sendable, Equatable, CaseIterable {
    /// The parse failed, so there is no document to take the values from.
    case noDocument
    /// The document has no chip (it is a visa, for example).
    case documentHasNoChip
    /// A field is empty.
    case empty
    /// A field has the wrong length.
    case wrongLength
    /// A field has a character the key cannot hold.
    case characterNotAllowed
    /// A long document number lacks its continuation in the optional data.
    case numberContinuationMissing
    /// A problem this version does not know.
    case unknown

    init(_ problem: MrzKeyProblem) {
        switch problem {
        case .noDocument: self = .noDocument
        case .documentHasNoChip: self = .documentHasNoChip
        case .empty: self = .empty
        case .wrongLength: self = .wrongLength
        case .characterNotAllowed: self = .characterNotAllowed
        case .numberContinuationMissing: self = .numberContinuationMissing
        default: self = .unknown
        }
    }
}

/// Why no card access number (CAN) key could be made. Mirrors `CanKeyProblem`.
///
/// - Since: 1.0.0
public enum ChipCanProblem: String, Sendable, Equatable, CaseIterable {
    /// The number is empty.
    case empty
    /// The number has a character that is not a digit `0` to `9`.
    case characterNotAllowed
    /// A problem this version does not know.
    case unknown

    init(_ problem: CanKeyProblem) {
        switch problem {
        case .empty: self = .empty
        case .characterNotAllowed: self = .characterNotAllowed
        default: self = .unknown
        }
    }
}

/// Why a chip access key could not be made. The text never holds the values you gave.
///
/// - Since: 1.0.0
public enum ChipAccessKeyError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A check digit given to ``Tessera/ChipAccessKey/fromMrz(documentNumber:documentNumberCheckDigit:dateOfBirth:dateOfBirthCheckDigit:dateOfExpiry:dateOfExpiryCheckDigit:)``
    /// was not exactly one character that fits in 16 bits (an emoji, for example).
    case checkDigitNotOneCharacter(parameter: String)
    /// The reader refused a value. `message` names the field, never its value.
    case invalid(message: String)
    /// No key could be built from the MRZ. `field` is the field at fault, when one is; `problem`
    /// says what was wrong with it. Neither holds a value.
    case notBuilt(field: ChipKeyField?, problem: ChipKeyProblem)
    /// No key could be built from the card access number. `characterIndex` is the place of the first
    /// character that is not a digit, counted from 0, for `.characterNotAllowed`; never the character.
    case canNotBuilt(problem: ChipCanProblem, characterIndex: Int?)

    /// A short plain-text description of the error.
    public var description: String {
        switch self {
        case .checkDigitNotOneCharacter(let parameter): return "\(parameter) must be one character"
        case .invalid(let message): return message
        case .notBuilt(let field, let problem):
            return "no key: \(problem.rawValue)" + (field.map { " (\($0.rawValue))" } ?? "")
        case .canNotBuilt(let problem, let characterIndex):
            return "no CAN key: \(problem.rawValue)" + (characterIndex.map { " (at index \($0))" } ?? "")
        }
    }
}

extension ChipAccessKeyError {
    /// Maps the Kotlin answer: the key, or the field and problem.
    static func unwrap(_ result: MrzKeyResult) throws -> ChipAccessKey.Mrz {
        switch result {
        case let built as MrzKeyResult.Built:
            return built.key
        case let notBuilt as MrzKeyResult.NotBuilt:
            throw ChipAccessKeyError.notBuilt(
                field: notBuilt.field.map(ChipKeyField.init),
                problem: ChipKeyProblem(notBuilt.problem)
            )
        default:
            throw ChipAccessKeyError.notBuilt(field: nil, problem: .unknown)
        }
    }
}

extension ChipAccessKeyError {
    /// Maps the Kotlin answer for a CAN: the key, or the problem and where it is.
    static func unwrap(_ result: CanKeyResult) throws -> ChipAccessKey.Can {
        switch result {
        case let built as CanKeyResult.Built:
            return built.key
        case let notBuilt as CanKeyResult.NotBuilt:
            throw ChipAccessKeyError.canNotBuilt(
                problem: ChipCanProblem(notBuilt.problem),
                characterIndex: notBuilt.characterIndex.map { Int($0.int32Value) }
            )
        default:
            throw ChipAccessKeyError.canNotBuilt(problem: .unknown, characterIndex: nil)
        }
    }
}

/// The three typed MRZ values after the SDK tidied them, and which of them it changed. The SDK trims
/// spaces at both ends and upper-cases ASCII letters; it changes nothing else. Holds the values you
/// typed, so treat it like the key: never log it or show it.
///
/// - Since: 1.0.0
public struct NormalizedTypedFields: Sendable, Equatable {
    /// The document number after tidying.
    public let documentNumber: String
    /// The date of birth after tidying.
    public let dateOfBirth: String
    /// The date of expiry after tidying.
    public let dateOfExpiry: String
    /// The fields whose text changed, in the order document number, date of birth, date of expiry.
    public let changedFields: [ChipKeyField]

    /// `true` when at least one field changed.
    public var wasChanged: Bool { !changedFields.isEmpty }

    /// Creates the value from the three tidied fields and the list of fields that changed.
    public init(documentNumber: String, dateOfBirth: String, dateOfExpiry: String, changedFields: [ChipKeyField] = []) {
        self.documentNumber = documentNumber
        self.dateOfBirth = dateOfBirth
        self.dateOfExpiry = dateOfExpiry
        self.changedFields = changedFields
    }

    init(_ fields: NormalizedMrzFields) {
        let changed = Set(fields.changedFields.map(ChipKeyField.init))
        self.init(
            documentNumber: fields.documentNumber,
            dateOfBirth: fields.dateOfBirth,
            dateOfExpiry: fields.dateOfExpiry,
            changedFields: [ChipKeyField.documentNumber, .dateOfBirth, .dateOfExpiry].filter(changed.contains)
        )
    }
}

extension ChipAccessKey {
    /// A key from a parsed document: the three MRZ values and their check digits are taken from it.
    /// The check digits are the ones printed; a wrong one is a finding on the key, never corrected.
    ///
    /// ```swift
    /// let key = try ChipAccessKey.from(document: document)
    /// ```
    ///
    /// - Throws: ``ChipAccessKeyError/notBuilt(field:problem:)`` when the document has no chip or a
    ///   field cannot make a key.
    public static func from(document: MrzDocument) throws -> ChipAccessKey.Mrz {
        try ChipAccessKeyError.unwrap(ChipAccessKey.Mrz.companion.from(document: document))
    }

    /// A key from the parse result the scanner gives (`ParseResult`): a success or a partial
    /// success holds a document, a failure does not.
    ///
    /// - Throws: ``ChipAccessKeyError/notBuilt(field:problem:)``, with `.noDocument` for a failed parse.
    public static func from(parse result: ParseResult) throws -> ChipAccessKey.Mrz {
        try ChipAccessKeyError.unwrap(ChipAccessKey.Mrz.companion.from(result: result))
    }

    /// The typed values, tidied the way ``fromTypedFields(documentNumber:dateOfBirth:dateOfExpiry:)``
    /// needs them: spaces at both ends trimmed and ASCII letters upper-cased, nothing else changed.
    /// Call it on what a text field gave you, then build the key from the result. It says which
    /// fields it changed, so you can show the person what you did.
    ///
    /// ```swift
    /// let typed = ChipAccessKey.normalizeTypedFields(
    ///     documentNumber: field1, dateOfBirth: field2, dateOfExpiry: field3)
    /// let key = try ChipAccessKey.fromTypedFields(
    ///     documentNumber: typed.documentNumber, dateOfBirth: typed.dateOfBirth,
    ///     dateOfExpiry: typed.dateOfExpiry)
    /// ```
    public static func normalizeTypedFields(
        documentNumber: String,
        dateOfBirth: String,
        dateOfExpiry: String
    ) -> NormalizedTypedFields {
        NormalizedTypedFields(
            ChipAccessKey.Mrz.companion.normalizeTypedFields(
                documentNumber: documentNumber, dateOfBirth: dateOfBirth, dateOfExpiry: dateOfExpiry)
        )
    }

    /// A key from values a person typed in: no check digits, the SDK works them out. Use this when
    /// the person reads the three values off the document. It is strict and changes nothing: for text
    /// from a text field, pass it through ``normalizeTypedFields(documentNumber:dateOfBirth:dateOfExpiry:)``
    /// first.
    ///
    /// - Throws: ``ChipAccessKeyError/notBuilt(field:problem:)`` with the field at fault.
    public static func fromTypedFields(
        documentNumber: String,
        dateOfBirth: String,
        dateOfExpiry: String
    ) throws -> ChipAccessKey.Mrz {
        try ChipAccessKeyError.unwrap(
            ChipAccessKey.Mrz.companion.fromTypedFields(
                documentNumber: documentNumber, dateOfBirth: dateOfBirth, dateOfExpiry: dateOfExpiry)
        )
    }

    /// A key from the MRZ: the three values, each with its check digit, as printed.
    ///
    /// Give the values exactly as printed, fillers (`<`) included, and the check digits as printed,
    /// even when one does not match: the SDK never corrects them. For a TD1 or TD2 number longer than
    /// nine characters, build the key with `ChipAccessKey.Mrz.companion.fromPrintedFields(...)`.
    ///
    /// ```swift
    /// let key = try ChipAccessKey.fromMrz(
    ///     documentNumber: "L898902C3", documentNumberCheckDigit: "6",
    ///     dateOfBirth: "740812", dateOfBirthCheckDigit: "2",
    ///     dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9")
    /// ```
    ///
    /// - Throws: ``ChipAccessKeyError``.
    public static func fromMrz(
        documentNumber: String,
        documentNumberCheckDigit: Character,
        dateOfBirth: String,
        dateOfBirthCheckDigit: Character,
        dateOfExpiry: String,
        dateOfExpiryCheckDigit: Character
    ) throws -> ChipAccessKey {
        let digits = [
            try Self.unit(documentNumberCheckDigit, "documentNumberCheckDigit"),
            try Self.unit(dateOfBirthCheckDigit, "dateOfBirthCheckDigit"),
            try Self.unit(dateOfExpiryCheckDigit, "dateOfExpiryCheckDigit"),
        ]
        do {
            return try ChipAccessKey.Mrz(
                documentNumber: documentNumber,
                documentNumberCheckDigit: digits[0],
                dateOfBirth: dateOfBirth,
                dateOfBirthCheckDigit: digits[1],
                dateOfExpiry: dateOfExpiry,
                dateOfExpiryCheckDigit: digits[2]
            )
        } catch {
            throw ChipAccessKeyError.invalid(message: error.localizedDescription)
        }
    }

    /// A key from the card access number (CAN): the short number printed on the document.
    /// Digits only, at least one.
    ///
    /// - Throws: ``ChipAccessKeyError/canNotBuilt(problem:characterIndex:)`` when `can` is empty or
    ///   holds a character other than `0` to `9`. The error never holds the number.
    public static func fromCan(_ can: String) throws -> ChipAccessKey {
        try ChipAccessKeyError.unwrap(ChipAccessKey.Can.companion.from(can: can))
    }

    private static func unit(_ character: Character, _ parameter: String) throws -> unichar {
        let units = Array(String(character).utf16)
        guard units.count == 1 else { throw ChipAccessKeyError.checkDigitNotOneCharacter(parameter: parameter) }
        return units[0]
    }
}
