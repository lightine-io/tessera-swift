import Testing
import Tessera
@testable import TesseraKit

/// The key helpers: Swift errors instead of raw `NSError`, and no value in an error message.
/// The MRZ values are the published ICAO Doc 9303 specimen.
struct ChipAccessKeyBuildersTests {
    @Test func canKeyIsMade() throws {
        let key = try ChipAccessKey.fromCan("123456")
        #expect(key is ChipAccessKey.Can)
        #expect(!key.isCleared)
    }

    @Test func emptyCanAndLetterCanThrowOurError() {
        for bad in ["", "12a456"] {
            do {
                _ = try ChipAccessKey.fromCan(bad)
                Issue.record("expected an error for a bad CAN")
            } catch let error as ChipAccessKeyError {
                guard case .invalid(let message) = error else { Issue.record("wrong case"); continue }
                if !bad.isEmpty { #expect(!message.contains(bad)) }
            } catch {
                Issue.record("not a ChipAccessKeyError: \(error)")
            }
        }
    }

    @Test func mrzKeyIsMadeFromTypedFields() throws {
        let key = try ChipAccessKey.fromMrz(
            documentNumber: "L898902C3", documentNumberCheckDigit: "6",
            dateOfBirth: "740812", dateOfBirthCheckDigit: "2",
            dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
        )
        let mrz = try #require(key as? ChipAccessKey.Mrz)
        #expect(mrz.checkDigitFindings.isEmpty)
    }

    @Test func aWrongCheckDigitIsAFindingNotAnError() throws {
        let key = try ChipAccessKey.fromMrz(
            documentNumber: "L898902C3", documentNumberCheckDigit: "0",
            dateOfBirth: "740812", dateOfBirthCheckDigit: "2",
            dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
        )
        #expect(!(try #require(key as? ChipAccessKey.Mrz)).checkDigitFindings.isEmpty)
    }

    @Test func aBadLengthThrowsOurError() {
        #expect(throws: ChipAccessKeyError.self) {
            _ = try ChipAccessKey.fromMrz(
                documentNumber: "L898902C3", documentNumberCheckDigit: "6",
                dateOfBirth: "7408", dateOfBirthCheckDigit: "2",
                dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
            )
        }
    }

    @Test func aCheckDigitOfTwoUnitsThrows() {
        #expect(throws: ChipAccessKeyError.checkDigitNotOneCharacter(parameter: "dateOfBirthCheckDigit")) {
            _ = try ChipAccessKey.fromMrz(
                documentNumber: "L898902C3", documentNumberCheckDigit: "6",
                dateOfBirth: "740812", dateOfBirthCheckDigit: "\u{1F600}",
                dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
            )
        }
    }
}
