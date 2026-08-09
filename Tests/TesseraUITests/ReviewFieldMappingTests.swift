import Testing
import Tessera
@testable import TesseraUI

/// Locks the decode → document → common-field extraction the review screen's summary rows are built from,
/// against the ICAO Doc 9303 published TD3 specimen (fictional Utopia — a permitted test vector). This file
/// used to be a print-only diagnostic; TES-83 flagged that a test with no assertions can never fail, so the
/// printed values are now pinned — a field-mapping regression (e.g. a name appearing in the expiry row)
/// fails here as text, without rendering the UI.
struct ReviewFieldMappingTests {
    @Test func specimenCommonFieldsCarryTheExpectedRowValues() {
        let mrz = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        let decoded = assembleManualDecoded(text: mrz)
        let doc: MrzDocument
        if let s = decoded.parse as? ParseResult.Success {
            doc = s.document
        } else if let p = decoded.parse as? ParseResult.PartialSuccess {
            doc = p.document
        } else {
            Issue.record("the specimen must parse to a document; got \(type(of: decoded.parse))")
            return
        }

        let f = doc.commonFields
        // Identifiers per the SDK's contract: primary verbatim, secondary with filler rendered as spaces.
        #expect(f.primaryIdentifier == "ERIKSSON")
        #expect(f.secondaryIdentifier == "ANNA MARIA")
        #expect(f.documentNumber == "L898902C3")
        // Raw date components verbatim (the expiry's century deliberately may not resolve for this old
        // specimen — see the TES-94 changelog note — so only the raw components are pinned).
        #expect("\(f.dateOfBirth.rawYear)\(f.dateOfBirth.rawMonth)\(f.dateOfBirth.rawDay)" == "740812")
        #expect("\(f.dateOfExpiry.rawYear)\(f.dateOfExpiry.rawMonth)\(f.dateOfExpiry.rawDay)" == "120415")
        // The character on the document, verbatim (unichar 70 == "F") — the transparency stance shows this,
        // not a derived enum.
        #expect(f.rawSex == 70)
    }
}
