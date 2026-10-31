import Testing
import Tessera
@testable import TesseraUI

/// Call-site check for the 0.6.0 generator as a Swift consumer writes it (TES-223): the same ICAO Doc 9303
/// published TD3 specimen ("UTO" = fictional Utopia, a permitted test vector, not real document data) comes
/// back from `MrzGenerator` both from field values and from a parsed document.
struct GenerationCallSiteTests {
    private static let specimenLines = [
        "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
        "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
    ]

    @Test func generatesTheSpecimenFromFieldValues() {
        let result = MrzGenerator.shared.generateTD3(
            documentType: "P", issuingState: "UTO", documentNumber: "L898902C3",
            primaryIdentifier: "ERIKSSON", secondaryIdentifier: "ANNA MARIA", nationality: "UTO",
            dateOfBirth: Kotlinx_datetimeLocalDate(year: 1974, month: 8, day: 12), sex: .female,
            dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2012, month: 4, day: 15),
            personalNumber: "ZE184226B", transliteration: nil)
        guard let success = result as? GenerationResult.Success else {
            Issue.record("expected GenerationResult.Success, got \(type(of: result))")
            return
        }
        let lines: [String] = success.mrz
        #expect(lines == Self.specimenLines)
    }

    @Test func generatesTheSpecimenFromAParsedDocument() {
        let parsed = MrzParser.shared.parse(
            input: Self.specimenLines.joined(separator: "\n"), referenceTime: nowInstant())
        let document: TD3
        if let s = parsed as? ParseResult.Success, let td3 = s.document as? TD3 {
            document = td3
        } else if let p = parsed as? ParseResult.PartialSuccess, let td3 = p.document as? TD3 {
            document = td3
        } else {
            Issue.record("the specimen must parse to a TD3; got \(type(of: parsed))")
            return
        }
        for result in [MrzGenerator.shared.generate(td3: document),
                       MrzGenerator.shared.generate(document: document as MrzDocument)] {
            guard let success = result as? GenerationResult.Success else {
                Issue.record("expected GenerationResult.Success, got \(type(of: result))")
                continue
            }
            let lines: [String] = success.mrz
            #expect(lines == Self.specimenLines)
        }
    }
}
