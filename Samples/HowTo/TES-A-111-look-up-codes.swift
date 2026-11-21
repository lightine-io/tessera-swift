// Sample for TES-A-111 "Look up country and document codes on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-111 block 1: Package.swift dependency lines

// region TES-A-111 block 2
import Tessera
// endregion

// region TES-A-111 block 3
func country(_ code: String) -> String {
    guard let entry = CountryCodeTable.shared.lookup(code: code) else { return "unknown" }
    return "\(entry.displayName) (\(entry.category.name))"
}
// country("UTO") is "Utopia (OTHER)". country("AZE") is "Azerbaijan (STATE)".
// endregion

// region TES-A-111 block 4
func documentType(_ code: String) -> String {
    guard let entry = DocumentTypeCodeTable.shared.lookup(code: code) else { return "unknown" }
    return "\(entry.displayName) (\(entry.category.name))"
}
// documentType("P") is "Passport (PASSPORT)". documentType("IA") is "unknown".
// endregion

// region TES-A-111 block 5
func issuer(of document: MrzDocument) -> String {
    guard let code = document.commonFields.issuingState as? String else { return "unknown" }
    return country(code)
}
// endregion

// region TES-A-111 block 6
func isPassport(_ code: String) -> Bool {
    DocumentTypeCodeTable.shared.lookup(code: code)?.category === DocumentCategory.passport
}
// endregion

// region TES-A-111 block 7
func broadCategory(_ code: String) -> String {
    DocumentTypeCodeTable.shared.broadCategory(code: code)?.name ?? "unknown"
}
// broadCategory("IA") is "IDENTITY_CARD". broadCategory("XX") is "unknown".
// endregion

// region TES-A-111 block 8
func stateCodes() -> [String] {
    CountryCodeTable.shared.byCategory(category: CountryCodeCategory.state).map { $0.code }
}
// endregion
