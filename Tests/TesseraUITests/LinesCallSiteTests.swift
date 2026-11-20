import Testing
import Tessera
@testable import TesseraUI

/// Call-site check for the `lines:` overloads as a Swift consumer writes them (TES-289): `parse`, `read` and
/// `validate` take a list of MRZ lines and give the same kind of result as the one-string `input:` overloads.
/// The fixture is the ICAO Doc 9303 published TD3 specimen ("UTO" = fictional Utopia, a permitted test
/// vector, not real document data).
struct LinesCallSiteTests {
    private static let specimenLines = [
        "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
        "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
    ]
    private static let joined = specimenLines.joined(separator: "\n")

    @Test func parseTakesLines() {
        let now = nowInstant()
        let fromLines = MrzParser.shared.parse(lines: Self.specimenLines, referenceTime: now)
        let fromInput = MrzParser.shared.parse(input: Self.joined, referenceTime: now)
        #expect(!(fromLines is ParseResult.Failure))
        #expect(type(of: fromLines) == type(of: fromInput))
    }

    @Test func readTakesLinesAndStampsManualEntry() {
        let now = nowInstant()
        let fromLines = ManualMrzReader.shared.read(lines: Self.specimenLines, referenceTime: now)
        let fromInput = ManualMrzReader.shared.read(input: Self.joined, referenceTime: now)
        #expect(!(fromLines is ParseResult.Failure))
        #expect(type(of: fromLines) == type(of: fromInput))
        #expect(fromLines.metadata.readMethod == .manualEntry)
    }

    @Test func validateTakesLines() {
        let now = nowInstant()
        let fromLines = MrzValidator.shared.validate(lines: Self.specimenLines, referenceTime: now)
        let fromInput = MrzValidator.shared.validate(input: Self.joined, referenceTime: now)
        #expect(type(of: fromLines) == type(of: fromInput))
    }
}
