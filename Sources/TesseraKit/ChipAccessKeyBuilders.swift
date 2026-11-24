import Foundation
import Tessera

/// Why a chip access key could not be made. The text never holds the values you gave.
///
/// - Since: 1.0.0
public enum ChipAccessKeyError: Error, Sendable, Equatable {
    /// A check digit was not exactly one character that fits in 16 bits.
    case checkDigitNotOneCharacter(parameter: String)
    /// The reader refused a value. `message` names the field, never its value.
    case invalid(message: String)
}

extension ChipAccessKey {
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
    /// - Throws: ``ChipAccessKeyError`` when `can` is empty or holds a character other than `0` to `9`.
    public static func fromCan(_ can: String) throws -> ChipAccessKey {
        do {
            return try ChipAccessKey.Can(can: can)
        } catch {
            throw ChipAccessKeyError.invalid(message: error.localizedDescription)
        }
    }

    private static func unit(_ character: Character, _ parameter: String) throws -> unichar {
        let units = Array(String(character).utf16)
        guard units.count == 1 else { throw ChipAccessKeyError.checkDigitNotOneCharacter(parameter: parameter) }
        return units[0]
    }
}
