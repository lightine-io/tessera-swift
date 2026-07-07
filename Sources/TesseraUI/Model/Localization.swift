import Foundation

// Shared localization-format helper for the module's `tessera_scanner_*` string catalog.
//
// The catalog carries positional placeholders (`%1$@`, `%2$@`, `%1$d`, …), mirroring the Android module's
// positional `stringResource(..., arg1, arg2)` args so translators can reorder them. The screens format them
// by plain positional substitution rather than `String(format:)` — `String(format:)` with `%@`/`%s` and Swift
// `String` values is unreliable across platforms, so a predictable find-and-replace is used instead. All
// values are pre-stringified by the caller; the conversion character (`s`/`d`/`@`) is accepted for whichever
// style a given catalog entry uses.

/// Substitutes positional placeholders (`%1$s` / `%1$d` / `%1$@`, `%2$…`, …) in a localized template with the
/// given values, in order.
func substituting(_ template: String, _ values: String...) -> String {
    substituting(template, values)
}

/// Array form of ``substituting(_:_:)-swift.func``, for call sites that build the value list dynamically.
func substituting(_ template: String, _ values: [String]) -> String {
    var result = template
    for (index, value) in values.enumerated() {
        let position = index + 1
        for conversion in ["s", "d", "@"] {
            result = result.replacingOccurrences(of: "%\(position)$\(conversion)", with: value)
        }
    }
    return result
}
