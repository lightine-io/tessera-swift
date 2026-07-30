import SwiftUI

// The manual raw-MRZ entry screen (mockup 06) — the iOS mirror of the Android `ManualRawContent`. The user
// types the MRZ lines by hand; the SDK parses exactly what they typed and stamps the manual-entry read method
// as provenance (`ManualMrzReader`). Reader, not oracle (Principle 1): the format is always auto-detected from
// what was typed (TES-100 — the old Auto/Passport/ID-card hint picker is gone on both platforms); the live
// observations state neutral per-line character counts, never "invalid" and never an auto-correction.
// Everything the user typed is shown back verbatim (Principle 5).
//
// SCOPE (mirrors TES-63 / TES-79 on Android): this builds mockup 06 (raw MRZ entry) only. The field-by-field
// mode (mockup 06b) is DEFERRED — this screen shows the primary "Read what I typed" action only, not a
// secondary "Enter field by field" button.

/// The manual raw-MRZ entry screen. The user types the 1–3 MRZ lines (newline-separated) into a monospace
/// field; live neutral observations state each line's character count; a parse failure stays inline on this
/// screen (the typed text preserved — no jump to the camera-flavoured read-failed screen); and the primary
/// action hands the typed text back through ``onRead``.
///
/// - Parameters:
///   - text: the in-progress typed MRZ text (the model's hoisted draft — it survives method switches).
///   - parseFailed: whether the last "Read this" failed to parse; shown as an inline neutral note. Any edit
///     clears it (the model resets the flag on ``onTextChange``).
///   - onTextChange: called with the new text on every edit.
///   - onRead: called when the user taps the read action (format auto-detected).
///   - onBack: cancels manual entry (the flow reports Cancelled).
internal struct ManualEntryScreen: View {
    let text: String
    let parseFailed: Bool
    let onTextChange: (String) -> Void
    let onRead: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_manual_title", bundle: .module))
                .font(.title2.weight(.semibold))

            // The field + observations scroll; the two actions stay pinned below and always reachable —
            // mirrors the Android split between the scrollable Column and the pinned buttons.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Monospace, multi-line text field bound to the typed text. Uppercase + no autocorrect: an
                    // MRZ is upper-case A–Z / 0–9 / '<', and autocorrect would fight the user — but this only
                    // shapes the soft keyboard, it does not rewrite what is already typed (reader, not oracle).
                    // Forced left-to-right regardless of the ambient locale: an MRZ is always printed
                    // left-to-right per ICAO 9303, and RTL would mirror a string that must stay verbatim.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "tessera_scanner_manual_field_label", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(
                            text: Binding(
                                get: { text },
                                set: { onTextChange($0) }
                            )
                        )
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .accessibilityIdentifier("tessera-mrz-manual-raw-field")
                        .accessibilityLabel(String(localized: "tessera_scanner_manual_field_label", bundle: .module))
                    }

                    // The inline parse-failed note (mirrors the Android `parseFailed` inline path): neutral,
                    // the typed text stays, and any edit clears it. Never a jump to the read-failed screen —
                    // that screen's "blurred or partial" framing mislabels typed input.
                    if parseFailed {
                        Text(String(localized: "tessera_scanner_manual_parse_failed", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("tessera-mrz-manual-parse-failed")
                    }

                    Divider()

                    Text(String(localized: "tessera_scanner_review_observations_header", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(observations.enumerated()), id: \.offset) { _, note in
                            Label {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Text("ⓘ").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button {
                onRead()
            } label: {
                Text(String(localized: "tessera_scanner_manual_read", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-manual-read")

            Button {
                onBack()
            } label: {
                Text(String(localized: "tessera_scanner_cancel", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tessera-mrz-manual-cancel")
        }
        .padding(24)
        .contentMaxWidth()
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("tessera-mrz-manual-raw")
    }

    /// The live, neutral observation strings — one plain character count per typed line ("Line 2: 28
    /// characters"), grammatical for a count of one. No expected-length deltas: reading auto-detects the
    /// format, so no single expected length is known, and a delta would be a verdict in disguise (Principle 1).
    /// Mirrors the Android `manualObservations` plural resource.
    private var observations: [String] {
        manualLinesOf(text).enumerated().map { index, line in
            let key: String.LocalizationValue = line.count == 1
                ? "tessera_scanner_manual_obs_char_count_one"
                : "tessera_scanner_manual_obs_char_count_other"
            return substituting(String(localized: key, bundle: .module), "\(index + 1)", "\(line.count)")
        }
    }
}

// `substituting(...)` is the shared positional-format helper in Model/Localization.swift.
