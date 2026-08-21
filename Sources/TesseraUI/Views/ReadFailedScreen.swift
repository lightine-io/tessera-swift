import SwiftUI
import Tessera

// The "couldn't read this MRZ" screen (mockup 08) — the iOS mirror of the Android `ReadFailedContent`.
//
// Shown when OCR produced text that did not parse as any known MRZ format (a `ParseResult.Failure`). It states
// that honestly — never "invalid" — shows the captured text verbatim (garbles preserved, monospace, per-line
// horizontal scroll, never wrapped or truncated; Principle 5), and offers a retry or a switch to manual entry.
// Nothing on this screen judges the document: the SDK could not read the text, which is a different, honest
// statement than a verdict about validity (Principle 1).

/// The read-failed screen. Shows the raw captured OCR text exactly as read, with a retry and a manual-entry
/// escape. Mirrors the Android `ReadFailedContent`.
///
/// - Parameters:
///   - capturedText: the raw recognized text, exposed as-is (garbles preserved).
///   - onTryAgain: go back to scanning and try to read again.
///   - onManualEntry: switch to typing the details by hand.
internal struct ReadFailedScreen: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let capturedText: RecognizedText
    let onTryAgain: () -> Void
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry. Mirrors Android's `showManualEntry`.
    let showManualEntry: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TesseraStrings.string("tessera_scanner_read_failed_title", bundle: stringsBundle))
                .font(.title2.weight(.semibold))
                // A decode-landing too (OCR text that didn't parse) — announced on arrival so the outcome
                // ("Couldn't read this MRZ") reaches a screen-reader user, who needs to know to retry.
                .accessibilityAddTraits(.isHeader)

            Text(TesseraStrings.string("tessera_scanner_read_failed_body", bundle: stringsBundle))
                .font(.body)
                .foregroundStyle(.secondary)

            // The body + captured text scroll; the two actions stay pinned below and always reachable.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TesseraStrings.string("tessera_scanner_read_failed_captured_header", bundle: stringsBundle))
                        .font(.subheadline.weight(.semibold))
                    // Forced left-to-right regardless of the ambient locale — an MRZ is always printed
                    // left-to-right per ICAO 9303, and RTL would otherwise mirror the visual order of a
                    // string that must stay verbatim (Principle 5). Mirrors `ReviewScreen`'s own raw-MRZ use.
                    ForEach(Array(capturedText.lines.enumerated()), id: \.offset) { _, line in
                        MonoLine(line.text)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onTryAgain) {
                Text(TesseraStrings.string("tessera_scanner_read_failed_try_again", bundle: stringsBundle))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-read-failed-try-again")

            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(TesseraStrings.string("tessera_scanner_read_failed_manual", bundle: stringsBundle))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tessera-mrz-read-failed-manual")
            }
        }
        .padding(24)
        .contentMaxWidth()
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("tessera-mrz-read-failed")
    }
}
