// Sample for TES-A-115 "Read fields and dates from a parsed MRZ on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-115 block 1: Package.swift dependency lines

// region TES-A-115 block 2
import Foundation
import Tessera
// endregion

// region TES-A-115 block 3
func basics(_ document: MrzDocument) -> String {
    let fields = document.commonFields
    return "\(fields.primaryIdentifier), \(fields.secondaryIdentifier) | \(fields.documentNumber) | \(document.format.name)"
    // SPECIMEN, ALEX MORGAN | T22000129 | TD3
}
// endregion

// region TES-A-115 block 4
func codes(_ document: MrzDocument) -> [String] {
    let fields = document.commonFields
    return [fields.documentType, fields.issuingState, fields.nationality].map { ($0 as? String) ?? "\($0)" }
    // ["P", "UTO", "UTO"]
}
// endregion

// region TES-A-115 block 5
func sex(_ document: MrzDocument) -> String {
    let fields = document.commonFields
    let printed = Unicode.Scalar(fields.rawSex).map { String(Character($0)) } ?? ""
    return "\(printed) \(fields.sex.name)"   // F FEMALE
}
// endregion

// region TES-A-115 block 6
func expiry(_ date: MrzDate) -> String {
    if let resolved = date.computedDate { return resolved.description() }   // 2034-03-14
    return "unresolved \(date.rawYear)-\(date.rawMonth)-\(date.rawDay)"
}
// endregion

// region TES-A-115 block 7
func personalNumber(_ document: MrzDocument) -> String? {
    (document as? TD3)?.personalNumber   // S98765432<<<<<
}
// endregion

// region TES-A-115 block 8
func resolves(at epochMilliseconds: Int64) -> Bool {
    let time = KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: epochMilliseconds)
    let date = MrzDate.companion.parseExpiry(rawYear: "34", rawMonth: "03", rawDay: "14", referenceTime: time)
    return date.inferenceMethod !== MrzDateInferenceMethod.rawOnly
}
// resolves(at: 1_795_219_200_000) is true. resolves(at: 2_366_841_600_000) is false.
// endregion
