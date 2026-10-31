import Testing
import Tessera
@testable import TesseraUI

/// Coverage for the category the review screen's `documentDisplay` shows next to the raw type code. It comes
/// straight from the SDK's `DocumentTypeCodeTable.broadCategory(code:)` (TES-223): an exact table match first,
/// then the ICAO reserved-leading-character rule (Doc 9303 Part 4 §4.4 for P/V, Parts 5/6 for A/C/I). The rule
/// itself is tested in mrz-core; these pin that the Swift call site sees it. Synthetic codes only.
struct DocumentDisplayTests {
    @Test func reservedLeadingCharacterFallsBackToItsCategory() {
        // "IA" is not in DocumentTypeCodeTable (issuer-specific second letter per Parts 5/6), but 'I' is an
        // ICAO-reserved leading character for the identity-card family.
        let table = DocumentTypeCodeTable.shared
        #expect(table.broadCategory(code: "IA") === DocumentCategory.identityCard)
        #expect(table.broadCategory(code: "AX") === DocumentCategory.identityCard)
        #expect(table.broadCategory(code: "CX") === DocumentCategory.identityCard)
        #expect(table.broadCategory(code: "V") === DocumentCategory.visa)
    }

    @Test func unreservedLeadingCharacterStaysUncategorized() {
        // 'X' is not an ICAO-reserved leading character, so documentDisplay shows the raw code alone.
        #expect(DocumentTypeCodeTable.shared.broadCategory(code: "XY") == nil)
        #expect(DocumentTypeCodeTable.shared.broadCategory(code: "") == nil)
    }

    @Test func tableListedCodeResolvesViaTheExactMatchPath() {
        #expect(DocumentTypeCodeTable.shared.broadCategory(code: "P") === DocumentCategory.passport)
    }
}
