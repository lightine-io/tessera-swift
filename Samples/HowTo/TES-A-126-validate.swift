// Sample for TES-A-126 "Validate an MRZ on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-126 block 1: Package.swift dependency lines

// region TES-A-126 block 2
import Foundation
import Tessera

let tampered = """
P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
L898902C30UTO7408122F1204159ZE184226B<<<<<10
"""

func referenceTime() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_275_350_400_000)
}
// endregion

// region TES-A-126 block 3
func validateText() -> ValidationResult {
    MrzValidator.shared.validate(input: tampered, referenceTime: referenceTime())
}
// endregion

// region TES-A-126 block 4
func structuralProblem(_ result: ValidationResult) -> String? {
    result.structuralFailure?.description_
}
// endregion

// region TES-A-126 block 5
func failedChecks(_ result: ValidationResult) -> [String] {
    result.validationFailures.compactMap { failure in
        guard let mismatch = failure as? MrzCheckDigitMismatch else { return nil }
        let expected = String(utf16CodeUnits: [mismatch.expected], count: 1)
        let observed = String(utf16CodeUnits: [mismatch.observed], count: 1)
        return "\(mismatch.field.name): expected \(expected), observed \(observed)"
    }
    // DOCUMENT_NUMBER: expected 6, observed 0
    // COMPOSITE: expected 8, observed 0
}
// endregion

// region TES-A-126 block 6
func warnings(_ result: ValidationResult) -> [String] {
    result.warnings.map { $0.description_ }   // empty for this text
}
// endregion

// region TES-A-126 block 7
func validateAsPassport() -> ValidationResult {
    let lines = tampered.split(separator: "\n").map(String.init)
    return MrzValidator.shared.validate(lines: lines, format: MrzFormat.td3, referenceTime: referenceTime())
}
// endregion
