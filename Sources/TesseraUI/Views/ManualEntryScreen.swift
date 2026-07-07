import SwiftUI

// The manual raw-MRZ entry screen (mockup 06) — the iOS mirror of the Android `ManualRawContent`. The user
// types the MRZ lines by hand; the SDK parses exactly what they typed and stamps the manual-entry read method
// as provenance (`ManualMrzReader`). Reader, not oracle (Principle 1): the format picker is a parser *hint*
// only — it chooses which parser `onRead` runs, it never rewrites the input; the live observations state
// neutral length notes, never "invalid" and never an auto-correction. Everything the user typed is shown back
// verbatim (Principle 5).
//
// SCOPE (mirrors TES-63 / TES-79 on Android): this builds mockup 06 (raw MRZ entry) only. The field-by-field
// mode (mockup 06b) is DEFERRED — this screen shows the primary "Read what I typed" action only, not a
// secondary "Enter field by field" button.

/// The manual raw-MRZ entry screen. The user types the 1–3 MRZ lines (newline-separated) into a monospace
/// field; a format picker selects which parser ``onRead`` hint runs (a hint only — the input is never
/// rewritten); live neutral observations state each line's length; a privacy line states the read stays
/// on-device; and the primary action hands the typed text back through ``onRead``.
///
/// - Parameters:
///   - text: the in-progress typed MRZ text.
///   - onTextChange: called with the new text on every edit.
///   - onRead: called with the selected ``ManualFormatHint`` when the user taps "Read what I typed".
///   - onBack: cancels manual entry (the flow reports Cancelled).
internal struct ManualEntryScreen: View {
    let text: String
    let onTextChange: (String) -> Void
    let onRead: (ManualFormatHint) -> Void
    let onBack: () -> Void

    // The hint is a local UI concern (which parser to run), not part of the flow's persisted state — it never
    // changes the typed text, only how it is read. Mirrors the Android `var hint by remember { ... }`.
    @State private var hint: ManualFormatHint = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_manual_title", bundle: .module))
                .font(.title2.weight(.semibold))

            // The field + picker + observations scroll; the two actions stay pinned below and always
            // reachable — mirrors the Android split between the scrollable Column and the pinned buttons.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Monospace, multi-line text field bound to the typed text. Uppercase + no autocorrect: an
                    // MRZ is upper-case A–Z / 0–9 / '<', and autocorrect would fight the user — but this only
                    // shapes the soft keyboard, it does not rewrite what is already typed (reader, not oracle).
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
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .accessibilityIdentifier("tessera-mrz-manual-raw-field")
                        .accessibilityLabel(String(localized: "tessera_scanner_manual_field_label", bundle: .module))
                    }

                    // Format-hint picker: Auto (default) / Passport / ID card. Parser hints only.
                    Picker(String(localized: "tessera_scanner_manual_title", bundle: .module), selection: $hint) {
                        Text(String(localized: "tessera_scanner_manual_hint_auto", bundle: .module)).tag(ManualFormatHint.auto)
                        Text(String(localized: "tessera_scanner_manual_hint_passport", bundle: .module)).tag(ManualFormatHint.passport)
                        Text(String(localized: "tessera_scanner_manual_hint_id_card", bundle: .module)).tag(ManualFormatHint.idCard)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tessera-mrz-manual-format-hint")

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

                    Text(String(localized: "tessera_scanner_manual_privacy", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onRead(hint)
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

    /// The live, neutral observation strings — a length note per typed line plus the standing hint-not-fixes
    /// note. Every note is a neutral observation, never a verdict (Principle 1): under Auto only the char
    /// count is stated (no single expected length is known); under Passport / ID card a line whose length
    /// differs from the expected length gets a neutral "short by N" / "over by N" note, and an exact match is
    /// silent (no noise). Mirrors the Android `manualObservations` / `manualObservationParts`.
    private var observations: [String] {
        let lines = manualLinesOf(text)
        let expected = hint.expectedLineLength
        var notes: [String] = lines.enumerated().compactMap { index, line in
            let lineNumber = index + 1
            let length = line.count
            guard let expected else {
                return substituting(
                    String(localized: "tessera_scanner_manual_obs_char_count", bundle: .module),
                    "\(lineNumber)",
                    "\(length)"
                )
            }
            if length < expected {
                return substituting(
                    String(localized: "tessera_scanner_manual_obs_short", bundle: .module),
                    "\(lineNumber)",
                    "\(expected - length)"
                )
            }
            if length > expected {
                return substituting(
                    String(localized: "tessera_scanner_manual_obs_over", bundle: .module),
                    "\(lineNumber)",
                    "\(length - expected)"
                )
            }
            // Exact match: no observation — silence rather than an "OK" verdict.
            return nil
        }
        notes.append(String(localized: "tessera_scanner_manual_obs_hint_note", bundle: .module))
        return notes
    }
}

// `substituting(...)` is the shared positional-format helper in Model/Localization.swift.
