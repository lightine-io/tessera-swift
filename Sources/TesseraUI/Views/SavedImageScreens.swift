import SwiftUI
import Tessera

// The saved-image (photo) reading screens (mockups 07c → 07 / 07b) — the iOS mirror of the Android
// `SavedImageScreen.kt`. A picked photo is read by the tolerant `SavedImageMrzReader`; because tolerant
// reading surfaces *every* parseable disambiguation of an ambiguous glyph without ranking or picking one
// (ADR-023 / Principle 1), the candidates screen lists them in the exact order returned — no "best", no
// highlight of a "match" — and every candidate is pickable regardless of its own check-digit verdict. The
// state mapping (`SavedImageOutcome`, `candidateDecoded`) lives in `Model/ScannerDecisions.swift`; these are
// the display views only.

// MARK: - Awaiting pick

/// The await-saved-image-pick prompt. Shown when the saved-image method is the entry point and the picker
/// was dismissed with no photo — so the screen is never left blank. Neutral copy ("Choose a photo" + the
/// on-device privacy fact) and a single action that re-opens the picker. Mirrors the Android
/// `AwaitingSavedImagePickContent`.
internal struct AwaitingSavedImagePickScreen: View {
    let onChoosePhoto: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Spacer()
                Text(String(localized: "tessera_scanner_saved_image_prompt_title", bundle: .module))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(String(localized: "tessera_scanner_saved_image_prompt_body", bundle: .module))
                    .font(.body)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Button(action: onChoosePhoto) {
                Text(String(localized: "tessera_scanner_saved_image_prompt_action", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-awaiting-pick")
    }
}

// MARK: - Analyzing

/// The "analyzing photo" screen (mockup 07c) — shown while the picked photo is being read on-device. A
/// loading indicator over a title and neutral sub-text, stating the on-device privacy fact plainly rather
/// than implying anything about the image. The title is announced to VoiceOver on arrival (this screen is
/// reached via an auto-transition, not a user tap), mirroring the Android polite live region; the spinner is
/// decorative and hidden from the accessibility tree. Mirrors the Android `SavedImageAnalyzingContent`.
internal struct SavedImageAnalyzingScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "tessera_scanner_saved_image_analyzing_title", bundle: .module))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.updatesFrequently)

            ProgressView()
                .controlSize(.large)
                .accessibilityHidden(true)

            Text(String(localized: "tessera_scanner_saved_image_analyzing_reading", bundle: .module))
                .font(.body)

            Text(String(localized: "tessera_scanner_saved_image_analyzing_on_device", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-analyzing")
    }
}

// MARK: - Candidates

/// The saved-image candidates screen (mockup 07). Tolerant reading resolved a genuinely ambiguous glyph more
/// than one way; this lists **every** parseable reconstruction, **in the order returned** — never re-ranked,
/// never with a "best" or "match" highlight (Principle 1 / ADR-023). Each card shows the candidate's reading
/// monospace with the differing glyph(s) emphasised, its own honest per-candidate check-digit observations,
/// and a "Use this" action enabled for every candidate regardless of its verdict — the user, not the SDK,
/// decides which reading is theirs. Mirrors the Android `SavedImageCandidatesContent`.
///
/// - Parameters:
///   - candidates: the SDK's candidate set, rendered as-is (order preserved, none dropped or promoted).
///   - onPick: the chosen candidate — the caller wraps it (``candidateDecoded(_:)``) and routes it.
///   - onChooseDifferent: re-launch the photo picker for a different image.
internal struct SavedImageCandidatesScreen: View {
    let candidates: [MrzCandidate]
    let onPick: (MrzCandidate) -> Void
    let onChooseDifferent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_saved_image_candidates_title", bundle: .module))
                .font(.title2.weight(.semibold))
            Text(
                String(
                    format: String(localized: "tessera_scanner_saved_image_candidates_intro", bundle: .module),
                    candidates.count
                )
            )
            .font(.body)

            ScrollView {
                VStack(spacing: 12) {
                    // In the order returned — the index maps a candidate to its own disambiguations.
                    // NEVER sorted, never re-ranked (Principle 1 / ADR-023).
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                        CandidateCard(candidate: candidate, onPick: { onPick(candidate) })
                    }
                }
            }

            Button(action: onChooseDifferent) {
                Text(String(localized: "tessera_scanner_saved_image_choose_different", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-candidates")
    }
}

/// One candidate card (mockup 07): the reconstructed MRZ lines with the resolved (differing) columns
/// emphasised, the candidate's own honest check-digit observations, and a "Use this" action. The differing
/// columns come from the candidate's ``MrzCandidate/disambiguations``, grouped per line so a multi-line MRZ
/// highlights the right glyph on the right line. No card is styled as preferred. Mirrors the Android
/// `CandidateCard`.
private struct CandidateCard: View {
    let candidate: MrzCandidate
    let onPick: () -> Void

    /// Which columns differ, per line — the positions this candidate resolved.
    private var highlightsByLine: [Int: Set<Int>] {
        Dictionary(grouping: candidate.disambiguations, by: { Int($0.lineIndex) })
            .mapValues { entries in Set(entries.map { Int($0.columnIndex) }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The reconstructed reading, each line monospace with its differing glyph(s) emphasised.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(candidate.mrzLines.enumerated()), id: \.offset) { lineIndex, line in
                    MonoLineHighlighted(text: line, highlightColumns: highlightsByLine[lineIndex] ?? [])
                }
            }

            // The candidate's own per-candidate verdict — the same honest check-digit reporting the review
            // screen uses, over this candidate's parse. Not a decision; just what its check digits say.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(candidateObservations(candidate.parse)) { observation in
                    CandidateObservationRow(observation)
                }
            }

            // Pickable regardless of the verdict — the user decides which reading is theirs.
            Button(action: onPick) {
                Text(String(localized: "tessera_scanner_saved_image_use_this", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

// `MonoLineHighlighted` is the shared component defined in ReviewScreen.swift (horizontal-scrolling, with the
// non-colour "differs here" accessibility label) — the candidates screen reuses it.

// MARK: - Empty

/// The "no MRZ found in this photo" screen (mockup 07b). Stated honestly — the MRZ *couldn't be located*, not
/// that the document is "invalid" — with a neutral hint about why, a privacy note that the photo stays
/// on-device, and two escapes: pick a different photo (primary) or type the details by hand (secondary).
/// Mirrors the Android `SavedImageEmptyContent`.
///
/// - Parameters:
///   - onChooseDifferent: re-launch the photo picker.
///   - onManualEntry: switch to manual raw-MRZ entry.
internal struct SavedImageEmptyScreen: View {
    let onChooseDifferent: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_saved_image_empty_title", bundle: .module))
                .font(.title2.weight(.semibold))
            Text(String(localized: "tessera_scanner_saved_image_empty_body", bundle: .module))
                .font(.body)
            Text(String(localized: "tessera_scanner_saved_image_empty_privacy", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onChooseDifferent) {
                Text(String(localized: "tessera_scanner_saved_image_choose_different", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onManualEntry) {
                Text(String(localized: "tessera_scanner_saved_image_manual", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-empty")
    }
}

// MARK: - Per-candidate check-digit observations

// A scoped, self-contained mirror of the Android `parseObservations` — narrowed to what a candidate card
// needs (the check-digit match/mismatch lines only; no provenance line, since a bare `ParseResult` carries
// none). Kept local to this file rather than shared with the not-yet-ported review screen; when
// ReviewScreen.swift lands, this should be reconciled with (or promoted alongside) its own observation model
// so the two don't drift — flagged here rather than silently duplicated.

/// The tone of a ``CandidateObservation`` — never a "valid"/"invalid" verdict, only what a check digit
/// reports. Mirrors the Android `ObservationTone`.
private enum CandidateObservationTone {
    case matches
    case mismatch
}

/// One honest observation line for a candidate's check-digit verdict. Mirrors the Android `Observation`,
/// narrowed to the check-digit-only subset a candidate card shows.
private struct CandidateObservation: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
    let tone: CandidateObservationTone
}

/// The check-digit observation set for a single parse verdict — document number, date of birth, date of
/// expiry always; optional-data and composite only when the format carries one. A mismatch states both the
/// recorded and computed digits; neither is "the right one" (the consumer decides — Principle 1). A
/// `ParseResultFailure` carries no parsed document, so it yields an empty list. Mirrors the check-digit
/// portion of the Android `parseObservations`.
private func candidateObservations(_ parse: ParseResult) -> [CandidateObservation] {
    let document: MrzDocument
    let metadata: ResultMetadata
    switch parse {
    case let success as ParseResult.Success:
        document = success.document
        metadata = success.metadata
    case let partial as ParseResult.PartialSuccess:
        document = partial.document
        metadata = partial.metadata
    default:
        return []
    }

    let fields = document.commonFields
    let mismatches = metadata.validationFailures.compactMap { $0 as? MrzCheckDigitMismatch }

    var checkedFields: [(MrzField, String)] = [
        (.documentNumber, String(localized: "tessera_scanner_check_label_document_number", bundle: .module)),
        (.dateOfBirth, String(localized: "tessera_scanner_check_label_date_of_birth", bundle: .module)),
        (.dateOfExpiry, String(localized: "tessera_scanner_check_label_date_of_expiry", bundle: .module)),
    ]
    if fields.checkDigits.optionalData != nil {
        checkedFields.append((.optionalData, String(localized: "tessera_scanner_check_label_optional_data", bundle: .module)))
    }
    if fields.checkDigits.composite != nil {
        checkedFields.append((.composite, String(localized: "tessera_scanner_check_label_composite", bundle: .module)))
    }

    return checkedFields.map { field, label in
        if let mismatch = mismatches.first(where: { $0.field == field }) {
            return CandidateObservation(
                symbol: "‼",
                text: String(
                    format: String(localized: "tessera_scanner_obs_check_mismatch", bundle: .module),
                    label,
                    String(uniCharacter: mismatch.observed),
                    String(uniCharacter: mismatch.expected)
                ),
                tone: .mismatch
            )
        }
        return CandidateObservation(
            symbol: "✓",
            text: String(format: String(localized: "tessera_scanner_obs_check_match", bundle: .module), label),
            tone: .matches
        )
    }
}

private extension String {
    /// Builds a one-character `String` from a Kotlin `unichar` (bridged as `UniChar` / `UInt16`) — the
    /// recorded/computed check-digit glyphs are single UTF-16 code units.
    init(uniCharacter: UniChar) {
        self = UnicodeScalar(uniCharacter).map(String.init) ?? ""
    }
}

/// Renders one ``CandidateObservation``: symbol + text, tinted by tone (never colour-only — the symbol and
/// text already carry the meaning). Mirrors the Android `ReviewObservationRow`, narrowed to this file's
/// observation model.
private struct CandidateObservationRow: View {
    let observation: CandidateObservation

    init(_ observation: CandidateObservation) {
        self.observation = observation
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(observation.symbol)
            Text(observation.text)
        }
        .font(.caption)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch observation.tone {
        case .matches: return .primary
        case .mismatch: return .orange
        }
    }
}
