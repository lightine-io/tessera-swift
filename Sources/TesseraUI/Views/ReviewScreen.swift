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
struct ReviewObservation: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
    let tone: ObservationTone
}

/// One key/value summary row: `label` on the start, monospace `value` on the end. Mirrors the Android
/// `FieldRow`.
struct FieldRow: Identifiable {
    let id = UUID()
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
    let decoded: MrzScanResultDecoded
    let expanded: Bool
    let onToggleExpanded: () -> Void
    let onUse: () -> Void
    let onRescan: () -> Void

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
            Text(String(localized: "tessera_scanner_review_title", bundle: .module))
                .font(.title2.weight(.semibold))
                // The review screen is the decode-landing: it appears the moment an MRZ is read. Announced on
                // arrival so a screen-reader user hears the outcome ("MRZ read").
                .accessibilityAddTraits(.isHeader)

            // The summary + observations + disclosure scroll; the two action buttons stay pinned below so they
            // are always reachable however long the observation list grows.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 8) {
                        ForEach(reviewSummaryRows(reviewDocument)) { SummaryRow($0) }
                    }

                    Divider()

                    Text(String(localized: "tessera_scanner_review_observations_header", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reviewObservations) { ReviewObservationRow($0) }
                    }

                    Button(action: onToggleExpanded) {
                        Text(String(localized: "tessera_scanner_review_show_all", bundle: .module))
                    }
                    .accessibilityIdentifier("tessera-mrz-review-show-all")
                }
            }

            Button(action: onUse) {
                Text(String(localized: "tessera_scanner_review_use", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-review-use")

            Button(action: onRescan) {
                Text(String(localized: "tessera_scanner_review_rescan", bundle: .module))
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

    // The expanded all-fields + raw-MRZ view (mockup 03c). The primary action here is `onUse`; there is no
    // rescan on the expanded view. A "Show less ▴" collapse returns to the summary.
    private var expandedBody: some View {
        let document = reviewDocument
        return VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_review_all_fields_title", bundle: .module))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reviewAllFieldRows(document)) { SummaryRow($0) }

                    Divider()

                    Text(String(localized: "tessera_scanner_review_raw_mrz_header", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(document.rawLines.enumerated()), id: \.offset) { _, line in
                        MonoLine(line)
                    }

                    ReviewObservationRow(
                        ReviewObservation(symbol: symbolInfo, text: scanQualityText, tone: .info)
                    )

                    Button(action: onToggleExpanded) {
                        Text(String(localized: "tessera_scanner_review_show_less", bundle: .module))
                    }
                    .accessibilityIdentifier("tessera-mrz-review-show-less")
                }
            }

            Button(action: onUse) {
                Text(String(localized: "tessera_scanner_review_use", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tessera-mrz-review-use")
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
            FieldRow(label: String(localized: "tessera_scanner_field_document", bundle: .module),
                     value: documentDisplay(fields.documentType)),
            FieldRow(label: String(localized: "tessera_scanner_field_name", bundle: .module),
                     value: nameDisplay(fields)),
            FieldRow(label: String(localized: "tessera_scanner_field_number", bundle: .module),
                     value: fields.documentNumber),
            FieldRow(label: String(localized: "tessera_scanner_field_expiry", bundle: .module),
                     value: dateDisplay(fields.dateOfExpiry)),
        ]
    }

    /// The full parsed field set (mockup 03c) — common fields plus a format-specific optional field. Mirrors
    /// the Android `reviewAllFieldRows`.
    private func reviewAllFieldRows(_ document: MrzDocument) -> [FieldRow] {
        let fields = document.commonFields
        var rows: [FieldRow] = [
            FieldRow(label: String(localized: "tessera_scanner_field_document_type", bundle: .module),
                     value: documentDisplay(fields.documentType)),
            FieldRow(label: String(localized: "tessera_scanner_field_issuing_state", bundle: .module),
                     value: countryDisplay(fields.issuingState)),
            FieldRow(label: String(localized: "tessera_scanner_field_name", bundle: .module),
                     value: nameDisplay(fields)),
            FieldRow(label: String(localized: "tessera_scanner_field_nationality", bundle: .module),
                     value: countryDisplay(fields.nationality)),
            FieldRow(label: String(localized: "tessera_scanner_field_date_of_birth", bundle: .module),
                     value: dateDisplay(fields.dateOfBirth)),
            // The actual character on the document (rawSex), per the transparency stance — not the derived enum.
            FieldRow(label: String(localized: "tessera_scanner_field_sex", bundle: .module),
                     value: charDisplay(fields.rawSex)),
            FieldRow(label: String(localized: "tessera_scanner_field_number", bundle: .module),
                     value: fields.documentNumber),
            FieldRow(label: String(localized: "tessera_scanner_field_expiry", bundle: .module),
                     value: dateDisplay(fields.dateOfExpiry)),
        ]
        // Format-specific optional / personal field, only when the format has one and it is not blank.
        let optional = optionalField(document)
        if let optional, !optional.isEmpty {
            rows.append(FieldRow(label: String(localized: "tessera_scanner_field_optional", bundle: .module), value: optional))
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
            text: substituting(String(localized: "tessera_scanner_obs_read_by", bundle: .module),
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
        for (field, label) in checkedFields {
            let mismatch = mismatches.first { $0.field === field }
            if let mismatch {
                observations.append(ReviewObservation(
                    symbol: symbolMismatch,
                    text: substituting(String(localized: "tessera_scanner_obs_check_mismatch", bundle: .module),
                                       label,
                                       unicharToString(mismatch.observed),
                                       unicharToString(mismatch.expected)),
                    tone: .mismatch
                ))
            } else {
                observations.append(ReviewObservation(
                    symbol: symbolMatch,
                    text: substituting(String(localized: "tessera_scanner_obs_check_match", bundle: .module), label),
                    tone: .matches
                ))
            }
        }

        // 2. Expiry well-formed (only when the components actually form a calendar date).
        if fields.dateOfExpiry.componentsFormCalendarDate?.boolValue == true {
            observations.append(ReviewObservation(
                symbol: symbolMatch,
                text: substituting(String(localized: "tessera_scanner_obs_expiry_well_formed", bundle: .module),
                                   dateDisplay(fields.dateOfExpiry)),
                tone: .matches
            ))
        }

        // 3. Neutral advisory when anything did not match.
        if !mismatches.isEmpty {
            observations.append(ReviewObservation(
                symbol: symbolInfo,
                text: String(localized: "tessera_scanner_obs_some_mismatch", bundle: .module),
                tone: .info
            ))
        }

        return observations
    }

    // MARK: - Display helpers

    private func nameDisplay(_ fields: CommonFields) -> String {
        substituting(String(localized: "tessera_scanner_name_format", bundle: .module),
                     fields.primaryIdentifier, fields.secondaryIdentifier)
    }

    /// "P — passport" from the raw type code and the recognized category; the raw code alone when the code is
    /// not in the lookup table. Mirrors the Android `documentDisplay`. `documentType` is a Kotlin `@JvmInline`
    /// value class over its `rawCode` string, so K/N erases it to that `String`; the category is re-derived via
    /// the exported `DocumentTypeCodeTable` lookup (the erased value carries no accessor of its own).
    private func documentDisplay(_ documentType: Any) -> String {
        let rawCode = (documentType as? String) ?? "\(documentType)"
        guard let entry = DocumentTypeCodeTable.shared.lookup(code: rawCode) else { return rawCode }
        return substituting(String(localized: "tessera_scanner_document_format", bundle: .module),
                            rawCode, categoryLabel(entry.category))
    }

    private func categoryLabel(_ category: DocumentCategory) -> String {
        // A Kotlin enum bridges as a class whose entries are singletons, so match by identity (`===`) rather
        // than a Swift `switch` (its cases are static properties, not Swift enum cases).
        if category === DocumentCategory.passport { return String(localized: "tessera_scanner_category_passport", bundle: .module) }
        if category === DocumentCategory.identityCard { return String(localized: "tessera_scanner_category_identity_card", bundle: .module) }
        if category === DocumentCategory.residencePermit { return String(localized: "tessera_scanner_category_residence_permit", bundle: .module) }
        if category === DocumentCategory.visa { return String(localized: "tessera_scanner_category_visa", bundle: .module) }
        return String(localized: "tessera_scanner_category_other", bundle: .module)
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
        if readMethod === ReadMethod.preCapturedImage { return String(localized: "tessera_scanner_read_method_photo", bundle: .module) }
        if readMethod === ReadMethod.manualEntry { return String(localized: "tessera_scanner_read_method_manual", bundle: .module) }
        // LIVE_CAMERA and any not-yet-surfaced provenance present as the live-camera label — this review path
        // is reached from the live camera.
        return String(localized: "tessera_scanner_read_method_live_camera", bundle: .module)
    }

    /// The scan-quality line for the expanded view: region status, OCR confidence, recognized line count.
    /// Mirrors the Android `scanQualityText`.
    private var scanQualityText: String {
        let quality = decoded.quality
        let region = quality.mrzRegionFound
            ? String(localized: "tessera_scanner_quality_region_found", bundle: .module)
            : String(localized: "tessera_scanner_quality_region_not_found", bundle: .module)
        let confidence = quality.ocrConfidence.map { formatConfidence($0.floatValue) }
            ?? String(localized: "tessera_scanner_quality_confidence_unknown", bundle: .module)
        return substituting(String(localized: "tessera_scanner_quality_format", bundle: .module),
                            region, confidence, "\(quality.recognizedLineCount)")
    }
}

// MARK: - Free display helpers (shared)

/// The computed calendar date when the SDK inferred one (ISO `YYYY-MM-DD` via `LocalDate.description`), else
/// the raw YYMMDD components exactly as recorded. Mirrors the Android `MrzDate.computedDateOrRaw`.
func dateDisplay(_ date: MrzDate) -> String {
    if let computed = date.computedDate { return computed.description() }
    return "\(date.rawYear)\(date.rawMonth)\(date.rawDay)"
}

/// Renders a `unichar` (K/N's bridging of a Kotlin `Char`) as a one-character Swift string. Used for check
/// digits and the raw sex glyph, shown verbatim.
func unicharToString(_ value: unichar) -> String {
    guard let scalar = Unicode.Scalar(value) else { return "" }
    return String(Character(scalar))
}

/// The raw glyph on the document, shown verbatim (the transparency stance) — mirrors `rawSex.toString()`.
func charDisplay(_ value: unichar) -> String { unicharToString(value) }

/// Two-decimal OCR confidence (e.g. 0.94), locale-independent so the value reads the same everywhere. Mirrors
/// the Android `formatConfidence`.
func formatConfidence(_ value: Float) -> String {
    let hundredths = min(max(Int(value * 100), 0), 100)
    let whole = hundredths / 100
    let frac = hundredths % 100
    return "\(whole).\(String(format: "%02d", frac))"
}

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

/// One MRZ line with the columns in `highlightColumns` emphasised — the differing glyphs a saved-image
/// candidate resolved (mockup 07). Same monospace, single-line, horizontally-scrollable, never-truncated shape
/// as ``MonoLine``, but each highlighted column is drawn bold and tinted. Non-colour a11y: the bold weight is
/// itself a non-colour signal, and a merged accessibility label appends a spoken "…, differs here" note so a
/// screen-reader user learns which characters differ. Mirrors the Android `MonoLineHighlighted`.
struct MonoLineHighlighted: View {
    let text: String
    let highlightColumns: Set<Int>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            styled
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var styled: Text {
        let chars = Array(text)
        var result = Text("")
        for (index, char) in chars.enumerated() {
            var piece = Text(String(char))
            if highlightColumns.contains(index) {
                piece = piece.fontWeight(.bold).foregroundColor(.accentColor)
            }
            result = result + piece
        }
        return result
    }

    private var accessibilityText: String {
        let hasHighlight = highlightColumns.contains { $0 >= 0 && $0 < text.count }
        guard hasHighlight else { return text }
        return "\(text), \(String(localized: "tessera_scanner_saved_image_differs_here", bundle: .module))"
    }
}

/// One observation line: its symbol and text, tinted by tone. The tone is carried non-visually two ways so it
/// never depends on colour alone (non-colour a11y): the literal ✓ / ‼ / ⓘ symbol is part of the text, and the
/// row's accessibility label names the tone in words (Match / Attention / Note) for a screen reader. Mirrors
/// the Android `ReviewObservationRow`.
struct ReviewObservationRow: View {
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
        case .matches: return String(localized: "tessera_scanner_obs_tone_match", bundle: .module)
        case .mismatch: return String(localized: "tessera_scanner_obs_tone_mismatch", bundle: .module)
        case .info: return String(localized: "tessera_scanner_obs_tone_info", bundle: .module)
        }
    }
}

// `substituting(...)` is the shared positional-format helper in Model/Localization.swift.
