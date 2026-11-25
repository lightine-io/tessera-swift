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

    // MARK: from a document, a scanned result and typed fields (the published ICAO specimen and the
    // project's own synthetic TD3 specimen; no real document data)

    private static let specimenLines = [
        "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
        "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
    ]

    private func parsed() -> ParseResult {
        MrzParser.shared.parse(lines: Self.specimenLines, referenceTime: KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_700_000_000_000))
    }

    @Test func aKeyIsMadeFromAParseResult() throws {
        let key = try ChipAccessKey.from(parse: parsed())
        #expect(!key.isCleared)
        #expect(key.checkDigitFindings.isEmpty)
    }

    @Test func aKeyIsMadeFromADocument() throws {
        let result = parsed()
        let document = try #require((result as? ParseResult.Success)?.document ?? (result as? ParseResult.PartialSuccess)?.document)
        let key = try ChipAccessKey.from(document: document)
        #expect(key.checkDigitFindings.isEmpty)
    }

    @Test func aFailedParseGivesNoDocumentAsASwiftError() {
        let failed = MrzParser.shared.parse(
            lines: ["not", "an mrz"], referenceTime: KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_700_000_000_000))
        #expect(failed is ParseResult.Failure)
        #expect(throws: ChipAccessKeyError.notBuilt(field: nil, problem: .noDocument)) {
            _ = try ChipAccessKey.from(parse: failed)
        }
    }

    @Test func typedFieldsGiveAKeyWithoutCheckDigits() throws {
        let key = try ChipAccessKey.fromTypedFields(documentNumber: "L898902C3", dateOfBirth: "740812", dateOfExpiry: "120415")
        #expect(key.checkDigitFindings.isEmpty)
    }

    @Test func aBadTypedFieldNamesTheFieldAndTheProblemButNotTheValue() {
        do {
            _ = try ChipAccessKey.fromTypedFields(documentNumber: "L898902C3", dateOfBirth: "7408", dateOfExpiry: "120415")
            Issue.record("expected an error")
        } catch let error as ChipAccessKeyError {
            guard case .notBuilt(let field, let problem) = error else { Issue.record("wrong case: \(error)"); return }
            #expect(field == .dateOfBirth)
            #expect(problem == .wrongLength)
            #expect(!error.description.contains("7408"))
        } catch {
            Issue.record("not a ChipAccessKeyError: \(error)")
        }
    }

    @Test func anEmptyTypedNumberIsProblemEmpty() {
        #expect(throws: ChipAccessKeyError.notBuilt(field: .documentNumber, problem: .empty)) {
            _ = try ChipAccessKey.fromTypedFields(documentNumber: "", dateOfBirth: "740812", dateOfExpiry: "120415")
        }
    }

    @Test func everyKotlinProblemAndFieldHasASwiftCase() {
        for problem in MrzKeyProblem.entries { #expect(ChipKeyProblem(problem) != .unknown) }
        for field in MrzField.entries { #expect(ChipKeyField(field) != .unknown) }
    }
}
