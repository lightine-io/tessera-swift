// Sample for TES-A-126 "Validate an MRZ on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-126 block 1: Package.swift dependency lines

// region TES-A-126 block 2
import Foundation
import Tessera

let tampered = """
P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<
T220001290UTO9003152F3403141S98765432<<<<<20
"""

func referenceTime() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_795_219_200_000)
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
    // DOCUMENT_NUMBER: expected 3, observed 0
    // COMPOSITE: expected 9, observed 0
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
