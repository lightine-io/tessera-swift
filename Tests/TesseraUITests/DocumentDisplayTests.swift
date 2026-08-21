import Testing
import Tessera
@testable import TesseraUI

/// Coverage for the Android→iOS parity fix (TES-111): `ReviewScreen.documentDisplay` must widen an exact
/// `DocumentTypeCodeTable` miss with the ICAO reserved-leading-character fallback, mirroring mrz-core's
/// `DocumentType.broadCategory` (TES-99) — which is not itself exported across the Kotlin/Native ObjC
/// boundary (`DocumentType` is a `@JvmInline value class`, erased to its raw `String`), so
/// `ReviewScreen.firstLetterCategory` re-implements the fallback's pure half locally. It is `static`
/// (internal) specifically so this pure mapping can be pinned directly, without standing up a full
/// `ReviewScreen` view or an MRZ decode. Synthetic codes only — never real document data.
struct DocumentDisplayTests {
    @Test func reservedLeadingCharacterFallsBackToItsCategory() {
        // "IA" is not in DocumentTypeCodeTable (issuer-specific second letter per Parts 5/6), but 'I' is an
        // ICAO-reserved leading character for the identity-card family.
        #expect(ReviewScreen.firstLetterCategory("IA") === DocumentCategory.identityCard)
        #expect(ReviewScreen.firstLetterCategory("AX") === DocumentCategory.identityCard)
        #expect(ReviewScreen.firstLetterCategory("CX") === DocumentCategory.identityCard)
        #expect(ReviewScreen.firstLetterCategory("V") === DocumentCategory.visa)
        #expect(ReviewScreen.firstLetterCategory("p") === DocumentCategory.passport, "case-insensitive on the first character")
    }

    @Test func unreservedLeadingCharacterStaysUncategorized() {
        // 'X' is not one of the ICAO-reserved leading characters (P/V/I/A/C), so the raw code alone should
        // carry through documentDisplay with no category fallback.
        #expect(ReviewScreen.firstLetterCategory("XY") == nil)
        #expect(ReviewScreen.firstLetterCategory("") == nil)
    }

    @Test func tableListedCodeStillResolvesViaTheExactMatchPath() {
        // "P" is one of the legacy single-character codes DocumentTypeCodeTable enumerates directly —
        // documentDisplay's primary (table) branch must still resolve it without falling through to
        // firstLetterCategory, exactly as before this fix.
        #expect(DocumentTypeCodeTable.shared.lookup(code: "P")?.category === DocumentCategory.passport)
    }
}
