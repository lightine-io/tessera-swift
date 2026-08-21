import SwiftUI
import Tessera

// The review screen (mockups 03 / 03b / 03c) — the iOS mirror of the Android `ReviewContent` /
// `ReviewExpandedContent` and their shared observation + field mappers in `ReviewScreen.kt`.
//
// Reader, not oracle (Principle 1). These screens state *observations* — never a "valid" / "invalid"
// verdict. A check digit "matches" or is shown as "recorded X, computed Y"; a date "is a well-formed date";
// provenance says how it was read. The primary action ("Use this result") stays ENABLED even when a check
// digit does not match, because reporting the mismatch and letting the consumer decide is exactly the SDK's
// job — it never blocks, disables, or auto-corrects. Every value is monospace and shown verbatim
// (Principle 5); the raw MRZ lines are never wrapped or truncated, only horizontally scrolled.

// MARK: - ReviewObservation model

/// The visual/semantic tone of an ``ReviewObservation``: whether it reports a match, a mismatch, or neutral info.
/// Mirrors the Android `ObservationTone`.
enum ObservationTone {
    /// A recorded value agrees with what the SDK computes (rendered ✓, tinted).
    case matches
    /// A recorded value disagrees with what the SDK computes (rendered ‼). Not "wrong" — just stated.
    case mismatch
    /// Neutral, informational (rendered ⓘ, muted): provenance, advisories, quality.
    case info
}

/// One stated observation about a reading — a symbol, its text, and its tone. The meaning lives in `text` and
/// in the tone's spoken prefix (see ``ReviewObservationRow``), never in colour alone, so it survives for a
/// screen-reader user (non-colour a11y). Mirrors the Android `ReviewObservation`.
struct ReviewObservation {
    let symbol: String
    let text: String
    let tone: ObservationTone
}

/// One key/value summary row: `label` on the start, monospace `value` on the end. Mirrors the Android
/// `FieldRow`. Deliberately NOT `Identifiable`: rows are rebuilt per body evaluation, so any stored id
/// would be fresh each time — the `ForEach`es render by stable position (`\.offset`) instead.
struct FieldRow {
    let label: String
    let value: String
}

// MARK: - The ✓ / ‼ / ⓘ marks used across the observation lines.
private let symbolMatch = "✓"
private let symbolMismatch = "‼"
private let symbolInfo = "ⓘ"

// MARK: - Screen

/// The review screen. Shows the curated summary and the honest observations for a decoded reading, with a
/// disclosure into the full field set and raw MRZ. `onUse` accepts the reading (enabled on a mismatch too);
/// `onRescan` discards it and goes back to scanning; `onToggleExpanded` flips the all-fields view. Mirrors the
/// Android `ReviewContent`.
///
/// - Parameters:
///   - decoded: the SDK's verbatim decode result, carried as-is (the UI adds no judgement).
///   - expanded: whether the all-fields + raw-MRZ view (mockup 03c) is shown instead of the summary.
///   - onToggleExpanded: flips `expanded`.
///   - onUse: accepts this reading as confirmed. Stays enabled on a check-digit mismatch (Principle 1).
///   - onRescan: discards the reading and returns to scanning.
internal struct ReviewScreen: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let decoded: MrzScanResultDecoded
    let expanded: Bool
    /// Which reading method produced this review — drives the provenance-aware secondary action label
    /// ("Rescan" / "Try another photo" / "Edit entry"), mirroring the Android `secondaryActionLabel`.
    let source: ScanMethod
    let onToggleExpanded: () -> Void
    let onUse: () -> Void
    let onRescan: () -> Void

    /// The collapsed summary's observation set: mismatches + the advisory + provenance ONLY — every passing
    /// ✓ check moves to the expanded view (TES-96). Mirrors the Android `reviewSummaryObservations`.
    private var reviewSummaryObservations: [ReviewObservation] {
        reviewObservations.filter { $0.tone != .matches }
    }

    /// "Rescan" / "Try another photo" / "Edit entry" per the review's source method.
    private var secondaryActionLabel: String {
        switch source {
        case .camera: TesseraStrings.string("tessera_scanner_review_rescan", bundle: stringsBundle)
        case .savedImage: TesseraStrings.string("tessera_scanner_review_try_another_photo", bundle: stringsBundle)
        case .manualEntry: TesseraStrings.string("tessera_scanner_review_edit_entry", bundle: stringsBundle)
        }
    }

    var body: some View {
        if expanded {
            expandedBody
        } else {
            summaryBody
        }
    }

    // The summary + honest observations + disclosure (mockups 03 / 03b).
    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TesseraStrings.string("tessera_scanner_review_title", bundle: stringsBundle))
                .font(.title2.weight(.semibold))
                // The review screen is the decode-landing: it appears the moment an MRZ is read. Announced on
                // arrival so a screen-reader user hears the outcome ("MRZ read").
                .accessibilityAddTraits(.isHeader)

            // The summary + observations + disclosure scroll; the two action buttons stay pinned below so they
            // are always reachable however long the observation list grows.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 8) {
                        ForEach(Array(reviewSummaryRows(reviewDocument).enumerated()), id: \.offset) { SummaryRow($0.element) }
                    }

                    Divider()

                    Text(TesseraStrings.string("tessera_scanner_review_observations_header", bundle: stringsBundle))
                        .font(.subheadline.weight(.semibold))
                    // Mismatches + advisory + provenance ONLY — every passing check moves to the expanded view
                    // (reviewObservations, unfiltered) rather than repeating a wall of ✓ rows here (TES-96).
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(reviewSummaryObservations.enumerated()), id: \.offset) { ReviewObservationRow($0.element) }
                    }

                    Button(action: onToggleExpanded) {
                        Text(TesseraStrings.string("tessera_scanner_review_show_all", bundle: stringsBundle))
                    }
                    .accessibilityIdentifier("tessera-mrz-review-show-all")
                }
            }

            Button(action: onUse) {
                Text(TesseraStrings.string("tessera_scanner_review_use", bundle: stringsBundle))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-review-use")

            Button(action: onRescan) {
                Text(secondaryActionLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tessera-mrz-review-rescan")
        }
        .padding(24)
        .contentMaxWidth()
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("tessera-mrz-review")
    }

    // The expanded all-fields + raw-MRZ view (mockup 03c). Shows the FULL observation set (every ✓ and ‼ row,
    // plus provenance — unlike the summary's mismatches-only view, TES-96) and every raw MRZ line, never
    // wrapped or truncated (forced left-to-right regardless of the ambient locale — Principle 5). The pinned
    // actions mirror the collapsed view's: `onUse` and the provenance-aware secondary action (Rescan / Try
    // another photo / Edit entry), so that action stays reachable here too. A "Show less ▴" collapse returns
    // to the summary.
    private var expandedBody: some View {
        let document = reviewDocument
        return VStack(alignment: .leading, spacing: 16) {
            Text(TesseraStrings.string("tessera_scanner_review_all_fields_title", bundle: stringsBundle))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(reviewAllFieldRows(document).enumerated()), id: \.offset) { SummaryRow($0.element) }

                    Divider()

                    Text(TesseraStrings.string("tessera_scanner_review_observations_header", bundle: stringsBundle))
                        .font(.subheadline.weight(.semibold))
                    // The FULL set — every ✓ match and ‼ mismatch, plus provenance — unlike the summary's
                    // mismatches-only view (TES-96).
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(reviewObservations.enumerated()), id: \.offset) { ReviewObservationRow($0.element) }
                    }

                    Divider()

                    Text(TesseraStrings.string("tessera_scanner_review_raw_mrz_header", bundle: stringsBundle))
                        .font(.subheadline.weight(.semibold))
                    // Forced left-to-right regardless of the ambient locale — an MRZ is always printed
                    // left-to-right per ICAO 9303, and RTL would otherwise mirror the visual order of a string
                    // that must stay verbatim (Principle 5).
                    ForEach(Array(document.rawLines.enumerated()), id: \.offset) { _, line in
                        MonoLine(line)
                    }
                    .environment(\.layoutDirection, .leftToRight)

                    Button(action: onToggleExpanded) {
                        Text(TesseraStrings.string("tessera_scanner_review_show_less", bundle: stringsBundle))
                    }
                    .accessibilityIdentifier("tessera-mrz-review-show-less")
                }
            }

            Button(action: onUse) {
                Text(TesseraStrings.string("tessera_scanner_review_use", bundle: stringsBundle))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-review-use")

            // Rescan / Try another photo / Edit entry, matching the collapsed view's provenance-aware label
            // (TES-96 — the expanded view previously dropped this action entirely).
            Button(action: onRescan) {
                Text(secondaryActionLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tessera-mrz-review-rescan")
        }
        .padding(24)
        .contentMaxWidth()
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("tessera-mrz-review-expanded")
    }

    // MARK: - Field mappers

    /// The document a non-failure decode carries. `ReviewScreen` is only shown for a Success / PartialSuccess
    /// (a Failure routes to the read-failed screen), so this always resolves. Mirrors the Android
    /// `reviewDocument`.
    private var reviewDocument: MrzDocument {
        if let success = decoded.parse as? ParseResult.Success { return success.document }
        if let partial = decoded.parse as? ParseResult.PartialSuccess { return partial.document }
        // Unreachable: the flow never shows ReviewScreen for a ParseResult.Failure.
        fatalError("ReviewScreen must not be shown for a parse failure")
    }

    /// The four summary rows (mockup 03): document, name, number, expiry. Mirrors the Android
    /// `reviewSummaryRows`.
    private func reviewSummaryRows(_ document: MrzDocument) -> [FieldRow] {
        let fields = document.commonFields
        return [
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_document", bundle: stringsBundle),
                     value: documentDisplay(fields.documentType)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_name", bundle: stringsBundle),
                     value: nameDisplay(fields)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_number", bundle: stringsBundle),
                     value: withoutTrailingFiller(fields.documentNumber)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_expiry", bundle: stringsBundle),
                     value: dateDisplay(fields.dateOfExpiry, bundle: stringsBundle)),
        ]
    }

    /// The full parsed field set (mockup 03c) — common fields plus a format-specific optional field. Mirrors
    /// the Android `reviewAllFieldRows`.
    private func reviewAllFieldRows(_ document: MrzDocument) -> [FieldRow] {
        let fields = document.commonFields
        var rows: [FieldRow] = [
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_document_type", bundle: stringsBundle),
                     value: documentDisplay(fields.documentType)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_issuing_state", bundle: stringsBundle),
                     value: countryDisplay(fields.issuingState)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_name", bundle: stringsBundle),
                     value: nameDisplay(fields)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_nationality", bundle: stringsBundle),
                     value: countryDisplay(fields.nationality)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_date_of_birth", bundle: stringsBundle),
                     value: dateDisplay(fields.dateOfBirth, bundle: stringsBundle)),
            // The actual character on the document (rawSex), per the transparency stance — not the derived enum.
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_sex", bundle: stringsBundle),
                     value: charDisplay(fields.rawSex)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_number", bundle: stringsBundle),
                     value: withoutTrailingFiller(fields.documentNumber)),
            FieldRow(label: TesseraStrings.string("tessera_scanner_field_expiry", bundle: stringsBundle),
                     value: dateDisplay(fields.dateOfExpiry, bundle: stringsBundle)),
        ]
        // Format-specific optional / personal field, only when the format has one and it is not blank AFTER
        // stripping trailing filler (an all-filler optional field, e.g. "<<<<<", must show no row at all
        // rather than an empty one — mirrors the Android `reviewAllFieldRows` filler-then-blank-check order).
        // TD3's field is specifically ICAO's "personal number" concept; every other format's optional data has
        // no such meaning, so it gets the neutral label (Principle 1) — mirrors the Android
        // `if (document is TD3) tessera_scanner_field_optional else tessera_scanner_field_optional_data`.
        let optional = optionalField(document).map(withoutTrailingFiller)
        if let optional, !optional.isEmpty {
            let labelKey = optionalFieldLabelKey(isTD3: document is TD3, forCheckDigit: false)
            rows.append(FieldRow(label: TesseraStrings.string(labelKey, bundle: stringsBundle), value: optional))
        }
        return rows
    }

    /// The format-specific optional / personal-number field, or `nil` when the format has none. Mirrors the
    /// `when (document)` block in the Android `reviewAllFieldRows`.
    private func optionalField(_ document: MrzDocument) -> String? {
        if let td3 = document as? TD3 { return td3.personalNumber }
        if let td2 = document as? TD2 { return td2.optionalData }
        if let mrvA = document as? MrvA { return mrvA.optionalData }
        if let mrvB = document as? MrvB { return mrvB.optionalData }
        if let td1 = document as? TD1 {
            return [td1.optionalData1, td1.optionalData2].first { !$0.isEmpty }
        }
        return nil
    }

    // MARK: - Observations

    /// The observation set for the decoded reading (mockups 03 / 03b): the shared per-check verdict from
    /// ``parseObservations`` plus a provenance INFO line naming the read method, slotted before the advisory so
    /// "some checks did not match" stays last. Mirrors the Android `reviewObservations`.
    private var reviewObservations: [ReviewObservation] {
        let parse = decoded.parse
        var observations = parseObservations(parse)
        // A Failure carries no document → no observations (this screen is never shown for one anyway).
        if parse is ParseResult.Failure { return observations }

        let provenance = ReviewObservation(
            symbol: symbolInfo,
            text: substituting(TesseraStrings.string("tessera_scanner_obs_read_by", bundle: stringsBundle),
                               readMethodLabel(parse.metadata.readMethod)),
            tone: .info
        )
        if let advisoryIndex = observations.firstIndex(where: { $0.tone == .info }) {
            observations.insert(provenance, at: advisoryIndex)
        } else {
            observations.append(provenance)
        }
        return observations
    }

    /// The honest per-check observation set for one parse verdict — check digits, expiry well-formedness, and a
    /// neutral advisory when anything did not match. Mirrors the Android `parseObservations`.
    private func parseObservations(_ parse: ParseResult) -> [ReviewObservation] {
        let document: MrzDocument
        if let success = parse as? ParseResult.Success { document = success.document }
        else if let partial = parse as? ParseResult.PartialSuccess { document = partial.document }
        else { return [] }

        let fields = document.commonFields
        // Only check-digit mismatches drive the per-field observations.
        let mismatches: [MrzCheckDigitMismatch] = parse.metadata.validationFailures
            .compactMap { $0 as? MrzCheckDigitMismatch }

        var observations: [ReviewObservation] = []

        // 1. Check digits present on this format. Document number, DOB, and expiry always carry one; optional-
        // data and composite only when the format has one (their MrzCheckDigits value is non-nil). Each is a
        // MATCH unless validationFailures reports a mismatch for it.
        var checkedFields: [(MrzField, String)] = [
            (.documentNumber, TesseraStrings.string("tessera_scanner_check_label_document_number", bundle: stringsBundle)),
            (.dateOfBirth, TesseraStrings.string("tessera_scanner_check_label_date_of_birth", bundle: stringsBundle)),
            (.dateOfExpiry, TesseraStrings.string("tessera_scanner_check_label_date_of_expiry", bundle: stringsBundle)),
        ]
        if fields.checkDigits.optionalData != nil {
            // TD3 reuses the "personal number" field label for this observation too, mirroring the field-row
            // choice above; every other format gets its own neutral check-digit label (Principle 1).
            let labelKey = optionalFieldLabelKey(isTD3: document is TD3, forCheckDigit: true)
            checkedFields.append((.optionalData, TesseraStrings.string(labelKey, bundle: stringsBundle)))
        }
        if fields.checkDigits.composite != nil {
            checkedFields.append((.composite, TesseraStrings.string("tessera_scanner_check_label_composite", bundle: stringsBundle)))
        }
        for (field, label) in checkedFields {
            let mismatch = mismatches.first { $0.field === field }
            if let mismatch {
                observations.append(ReviewObservation(
                    symbol: symbolMismatch,
                    text: substituting(TesseraStrings.string("tessera_scanner_obs_check_mismatch", bundle: stringsBundle),
                                       label,
                                       unicharToString(mismatch.observed),
                                       unicharToString(mismatch.expected)),
                    tone: .mismatch
                ))
            } else {
                observations.append(ReviewObservation(
                    symbol: symbolMatch,
                    text: substituting(TesseraStrings.string("tessera_scanner_obs_check_match", bundle: stringsBundle), label),
                    tone: .matches
                ))
            }
        }

        // 2. Expiry well-formed (only when the components actually form a calendar date).
        if fields.dateOfExpiry.componentsFormCalendarDate?.boolValue == true {
            observations.append(ReviewObservation(
                symbol: symbolMatch,
                text: substituting(TesseraStrings.string("tessera_scanner_obs_expiry_well_formed", bundle: stringsBundle),
                                   dateDisplay(fields.dateOfExpiry, bundle: stringsBundle)),
                tone: .matches
            ))
        }

        // 3. Neutral advisory when anything did not match.
        if !mismatches.isEmpty {
            observations.append(ReviewObservation(
                symbol: symbolInfo,
                text: TesseraStrings.string("tessera_scanner_obs_some_mismatch", bundle: stringsBundle),
                tone: .info
            ))
        }

        return observations
    }

    // MARK: - Display helpers

    private func nameDisplay(_ fields: CommonFields) -> String {
        substituting(TesseraStrings.string("tessera_scanner_name_format", bundle: stringsBundle),
                     fields.primaryIdentifier, fields.secondaryIdentifier)
    }

    /// "P — passport" from the raw type code and the recognized category; the raw code alone when the code is
    /// not in the lookup table. Mirrors the Android `documentDisplay`. `documentType` is a Kotlin `@JvmInline`
    /// value class over its `rawCode` string, so K/N erases it to that `String`; the category is re-derived via
    /// the exported `DocumentTypeCodeTable` lookup (the erased value carries no accessor of its own).
    private func documentDisplay(_ documentType: Any) -> String {
        let rawCode = (documentType as? String) ?? "\(documentType)"
        guard let entry = DocumentTypeCodeTable.shared.lookup(code: rawCode) else { return rawCode }
        return substituting(TesseraStrings.string("tessera_scanner_document_format", bundle: stringsBundle),
                            rawCode, categoryLabel(entry.category))
    }

    private func categoryLabel(_ category: DocumentCategory) -> String {
        // A Kotlin enum bridges as a class whose entries are singletons, so match by identity (`===`) rather
        // than a Swift `switch` (its cases are static properties, not Swift enum cases).
        if category === DocumentCategory.passport { return TesseraStrings.string("tessera_scanner_category_passport", bundle: stringsBundle) }
        if category === DocumentCategory.identityCard { return TesseraStrings.string("tessera_scanner_category_identity_card", bundle: stringsBundle) }
        if category === DocumentCategory.residencePermit { return TesseraStrings.string("tessera_scanner_category_residence_permit", bundle: stringsBundle) }
        if category === DocumentCategory.visa { return TesseraStrings.string("tessera_scanner_category_visa", bundle: stringsBundle) }
        return TesseraStrings.string("tessera_scanner_category_other", bundle: stringsBundle)
    }

    /// The country's display name when the code is recognized, else its raw three-letter code. `issuingState` /
    /// `nationality` are `CountryCode` value classes over `rawCode`, erased to `String`; the display name is
    /// re-derived via the exported `CountryCodeTable` lookup. Mirrors the Android `countryDisplay`.
    private func countryDisplay(_ country: Any) -> String {
        let rawCode = (country as? String) ?? "\(country)"
        return CountryCodeTable.shared.lookup(code: rawCode)?.displayName ?? rawCode
    }

    private func readMethodLabel(_ readMethod: ReadMethod) -> String {
        // Kotlin enum entries are class singletons — match by identity (`===`).
        if readMethod === ReadMethod.preCapturedImage { return TesseraStrings.string("tessera_scanner_read_method_photo", bundle: stringsBundle) }
        if readMethod === ReadMethod.manualEntry { return TesseraStrings.string("tessera_scanner_read_method_manual", bundle: stringsBundle) }
        // LIVE_CAMERA and any not-yet-surfaced provenance present as the live-camera label — this review path
        // is reached from the live camera.
        return TesseraStrings.string("tessera_scanner_read_method_live_camera", bundle: stringsBundle)
    }

}

// MARK: - Free display helpers (shared)

/// The computed calendar date when the SDK inferred one (ISO `YYYY-MM-DD` via `LocalDate.description`), else
/// the raw YYMMDD components labeled explicitly as unresolved (`94-06-23 (year not resolved)`) — TES-94. The
/// UI never re-derives a century itself; it only renders what the SDK already resolved, and labels the
/// fallback honestly rather than showing bare two-digit components that could pass for a confident date
/// (Principle 4). Mirrors the Android `dateDisplay` (`ReviewScreen.kt:748-751`).
func dateDisplay(_ date: MrzDate, bundle: Bundle?) -> String {
    if let computed = date.computedDate { return computed.description() }
    let raw = "\(date.rawYear)-\(date.rawMonth)-\(date.rawDay)"
    return substituting(TesseraStrings.string("tessera_scanner_date_unresolved_format", bundle: bundle), raw)
}

/// Strips trailing MRZ filler (`<`) from a parsed field VALUE for display — the fillers are fixed-width
/// padding, not data, so `L898902C<` reads as `L898902C`. Display-only: the raw MRZ section still renders
/// every character verbatim, so transparency is preserved (Principle 5). Mirrors the Android
/// `String.withoutTrailingFiller`.
func withoutTrailingFiller(_ value: String) -> String {
    var trimmed = Substring(value)
    while trimmed.hasSuffix("<") { trimmed = trimmed.dropLast() }
    return String(trimmed)
}

/// Renders a `unichar` (K/N's bridging of a Kotlin `Char`) as a one-character Swift string. Used for check
/// digits and the raw sex glyph, shown verbatim.
func unicharToString(_ value: unichar) -> String {
    guard let scalar = Unicode.Scalar(value) else { return "" }
    return String(Character(scalar))
}

/// The raw glyph on the document, shown verbatim (the transparency stance) — mirrors `rawSex.toString()`.
func charDisplay(_ value: unichar) -> String { unicharToString(value) }


// MARK: - Reusable components

/// A key/value summary row: label on the start, monospace value on the end. Mirrors the Android `SummaryRow`.
struct SummaryRow: View {
    let row: FieldRow
    init(_ row: FieldRow) { self.row = row }

    var body: some View {
        HStack {
            Text(row.label)
                .font(.body)
            Spacer()
            Text(row.value)
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }
}

/// One MRZ / captured-OCR line: monospace, on its own horizontally-scrollable row so a long line is never
/// wrapped or truncated (transparency — the consumer sees exactly what was read). Mirrors the Android
/// `MonoLine`.
struct MonoLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One observation line: its symbol and text, tinted by tone. The tone is carried non-visually two ways so it
/// never depends on colour alone (non-colour a11y): the literal ✓ / ‼ / ⓘ symbol is part of the text, and the
/// row's accessibility label names the tone in words (Match / Attention / Note) for a screen reader. Mirrors
/// the Android `ReviewObservationRow`.
struct ReviewObservationRow: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let observation: ReviewObservation
    init(_ observation: ReviewObservation) { self.observation = observation }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(observation.symbol)
                .foregroundStyle(color)
            Text(observation.text)
                .font(.body)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tonePrefix) \(observation.text)")
    }

    private var color: Color {
        switch observation.tone {
        case .matches: return .accentColor
        case .mismatch: return .orange
        case .info: return .secondary
        }
    }

    private var tonePrefix: String {
        switch observation.tone {
        case .matches: return TesseraStrings.string("tessera_scanner_obs_tone_match", bundle: stringsBundle)
        case .mismatch: return TesseraStrings.string("tessera_scanner_obs_tone_mismatch", bundle: stringsBundle)
        case .info: return TesseraStrings.string("tessera_scanner_obs_tone_info", bundle: stringsBundle)
        }
    }
}

// `substituting(...)` is the shared positional-format helper in Model/Localization.swift.
