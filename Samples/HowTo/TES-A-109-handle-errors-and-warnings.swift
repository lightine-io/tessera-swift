// Sample for TES-A-109 "Handle errors and warnings on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-109 block 1: Package.swift dependency lines

// region TES-A-109 block 2
import Tessera
// endregion

// region TES-A-109 block 3
func message(for error: MrzParseError) -> String {
    switch error {
    case let e as MrzFormatNotDetected:
        return "\(e.observedLineCount) lines do not match any format"
    case let e as MrzInvalidLength:
        return "\(e.format.name) needs \(e.expectedLineCount) lines of \(e.expectedLineLength) characters"
    case let e as MrzCharacterSetViolation:
        return "A character outside the MRZ alphabet at position \(e.position)"
    default:
        return error.description_
    }
}
// endregion

// region TES-A-109 block 4
func message(for failure: MrzValidationError) -> String {
    switch failure {
    case let f as MrzCheckDigitMismatch: return "Check digit mismatch in \(f.field.name)"
    case let f as MrzDateNotInCalendar: return "Not a calendar date in \(f.field.name)"
    case is MrzInvalidSexValue: return "Sex field outside M, F, X, and the filler"
    default: return failure.description_
    }
}
// endregion

// region TES-A-109 block 5
func isExpiryNote(_ warning: MrzWarning) -> Bool {
    warning is MrzExpiryDatePast || warning is MrzExpiryDateImplausiblyFar
}
// endregion

// region TES-A-109 block 6
func checkDigit(of field: String) -> String? {
    guard let digit = try? CheckDigitKt.computeCheckDigit(input: field) else { return nil }
    return String(utf16CodeUnits: [digit], count: 1)
}
// checkDigit(of: "T2200012<") is "4". checkDigit(of: "abc") is nil.
// endregion
