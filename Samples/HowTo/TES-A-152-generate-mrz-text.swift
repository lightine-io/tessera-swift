// Sample for TES-A-152 "Generate MRZ text on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-152 block 1: Package.swift dependency lines

// region TES-A-152 block 2
import Tessera
// endregion

// region TES-A-152 block 3
func passportLines() -> GenerationResult {
    MrzGenerator.shared.generateTD3(
        documentType: "P", issuingState: "UTO", documentNumber: "L898902C3",
        primaryIdentifier: "ERIKSSON", secondaryIdentifier: "ANNA MARIA", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1974, month: 8, day: 12), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2012, month: 4, day: 15),
        personalNumber: "ZE184226B", transliteration: nil
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
// P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
// L898902C36UTO7408122F1204159ZE184226B<<<<<10
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
        documentType: "P", issuingState: "UTO", documentNumber: "L898902C36",
        primaryIdentifier: "ERIKSSON", secondaryIdentifier: "ANNA MARIA", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1974, month: 8, day: 12), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2012, month: 4, day: 15),
        personalNumber: "ZE184226B", transliteration: nil
    )
}
// show(tooLong()) prints:
// Format TD3 field DOCUMENT_NUMBER expected at most 9 characters; observed 10 characters
// endregion
