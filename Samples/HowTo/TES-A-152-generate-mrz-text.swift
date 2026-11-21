// Sample for TES-A-152 "Generate MRZ text on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-152 block 1: Package.swift dependency lines

// region TES-A-152 block 2
import Tessera
// endregion

// region TES-A-152 block 3
func passportLines() -> GenerationResult {
    MrzGenerator.shared.generateTD3(
        documentType: "P", issuingState: "UTO", documentNumber: "T22000129",
        primaryIdentifier: "SPECIMEN", secondaryIdentifier: "ALEX MORGAN", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1990, month: 3, day: 15), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2034, month: 3, day: 14),
        personalNumber: "S98765432", transliteration: nil
    )
}
// endregion

// region TES-A-152 block 4
func show(_ result: GenerationResult) {
    if let success = result as? GenerationResult.Success {
        success.mrz.forEach { print($0) }
    } else if let failure = result as? GenerationResult.Failure {
        print(failure.error.description_)
    }
}
// show(passportLines()) prints:
// P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<
// T220001293UTO9003152F3403141S98765432<<<<<20
// endregion

// region TES-A-152 block 5
func regenerate(_ parsed: ParseResult.Success) -> GenerationResult {
    MrzGenerator.shared.generate(document: parsed.document)
}
// endregion

// region TES-A-152 block 6
func regeneratePassport(_ passport: TD3) -> GenerationResult {
    MrzGenerator.shared.generate(td3: passport)
}
// endregion

// region TES-A-152 block 7
func tooLong() -> GenerationResult {
    MrzGenerator.shared.generateTD3(
        documentType: "P", issuingState: "UTO", documentNumber: "T220001293",
        primaryIdentifier: "SPECIMEN", secondaryIdentifier: "ALEX MORGAN", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1990, month: 3, day: 15), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2034, month: 3, day: 14),
        personalNumber: "S98765432", transliteration: nil
    )
}
// show(tooLong()) prints:
// Format TD3 field DOCUMENT_NUMBER expected at most 9 characters; observed 10 characters
// endregion
