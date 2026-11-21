// Sample for TES-A-105 "Branch on a parse result on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-105 block 1: Package.swift dependency lines

// region TES-A-105 block 2
import Tessera
// endregion

// region TES-A-105 block 3
func summary(_ result: ParseResult) -> String {
    switch result {
    case let success as ParseResult.Success:
        return "Success: \(success.document.format.name)"
    case let partial as ParseResult.PartialSuccess:
        return "PartialSuccess: \(partial.metadata.validationFailures.count) failed checks"
    case let failure as ParseResult.Failure:
        return "Failure: \(failure.error.description_)"
    default:
        return "Unknown variant"
    }
}
// endregion

// region TES-A-105 block 4
func document(of result: ParseResult) -> MrzDocument? {
    if let success = result as? ParseResult.Success { return success.document }
    if let partial = result as? ParseResult.PartialSuccess { return partial.document }
    return nil
}
// endregion

// region TES-A-105 block 5
func notes(_ result: ParseResult) -> String {
    let metadata = result.metadata
    return "\(metadata.readMethod.name), \(metadata.warnings.count) warnings, \(metadata.validationFailures.count) failures"
}
// endregion
