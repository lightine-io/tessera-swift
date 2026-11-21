import Testing
import Tessera
@testable import TesseraUI

/// TES-152: the review screen states the parser's warnings as neutral notes. Observations only (reader, not
/// oracle): never a verdict, never blocking. Fixtures are the project's own TD3 specimen (fictional Utopia),
/// with the nationality code swapped for one that is not in the SDK's country table.
@MainActor
struct ReviewWarningObservationsTests {
    private static let specimen = """
    P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<
    T220001293UTO9003152F3403141S98765432<<<<<20
    """
    // Nationality (line 2, positions 11-13) is outside every check digit, so only the country code changes.
    private static let unknownNationality = specimen.replacingOccurrences(of: "293UTO9003152", with: "293XQZ9003152")

    private func observations(for text: String) -> (decoded: MrzScanResultDecoded, rows: [ReviewObservation]) {
        let decoded = assembleManualDecoded(text: text)
        let screen = ReviewScreen(decoded: decoded, expanded: true, source: .manualEntry,
                                  onToggleExpanded: {}, onUse: {}, onRescan: {})
        return (decoded, screen.reviewObservations)
    }

    private func isUnknownCountryNote(_ row: ReviewObservation) -> Bool {
        row.text.contains("isn't in our country list")
    }

    @Test func unknownNationalityYieldsANoteWithTheRawCode() {
        let (decoded, rows) = observations(for: Self.unknownNationality)
        #expect(!(decoded.parse is ParseResult.Failure)) // precondition
        let notes = rows.filter(isUnknownCountryNote)
        #expect(notes.count == 1)
        #expect(notes.first?.text.contains("XQZ") == true)
        #expect(notes.first?.tone == .info)
    }

    @Test func recognizedCountryYieldsNoUnknownCountryNote() {
        let (_, rows) = observations(for: Self.specimen)
        #expect(!rows.contains(where: isUnknownCountryNote))
    }

    @Test func noWarningNotesAppearBeyondTheOnesTheParserReported() {
        // Info rows are: provenance, one note per warning the screen has a text for, and the mismatch
        // advisory (absent here). "At most", not "exactly": a newer framework can report a warning type this
        // screen has no text for yet, and
        // such a warning shows no note. Each warning the screen does map has its own test above and below.
        let (decoded, rows) = observations(for: Self.specimen)
        let infoCount = rows.filter { $0.tone == .info }.count
        #expect(infoCount >= 1)
        #expect(infoCount <= 1 + decoded.parse.metadata.warnings.count)
    }

    @Test func expiryYearThatFitsNoCenturyIsANoteWithTheRawYear() throws {
        // Expiry year 99 fits neither the 2000s nor the 1900s inside the parser's window, so the parser reports
        // the century warning and the screen states it with the digits as printed.
        let unplaced = try expiryReplaced(Self.specimen, with: "990314")
        let (decoded, rows) = observations(for: unplaced)
        #expect(decoded.parse.metadata.warnings.contains { $0 is MrzExpiryDateCenturyNotInferred }) // precondition
        let notes = rows.filter { $0.text == "Expiry year 99 can't be placed in a century" }
        #expect(notes.count == 1)
        #expect(notes.first?.tone == .info)
    }

    @Test func onePassportLetterWithExpiryFrom2038IsANoteWithTheRawCode() throws {
        // The specimen's document code is "P<" (no second letter); an expiry in 2040 is past the limit.
        let late = try expiryReplaced(Self.specimen, with: "400314")
        let (decoded, rows) = observations(for: late)
        #expect(decoded.parse.metadata.warnings.contains { $0 is MrzExpiryDateAfterSingleLetterPassportLimit }) // precondition
        let notes = rows.filter { $0.text == "Passport code P< has no second letter, and ICAO says such passports expire before 2038" }
        #expect(notes.count == 1)
        #expect(notes.first?.tone == .info)
    }

    @Test func specimenYieldsNoSingleLetterPassportNote() {
        let (_, rows) = observations(for: Self.specimen)
        #expect(!rows.contains { $0.text.contains("has no second letter") })
    }

    @Test func specimenYieldsNoCenturyNote() {
        let (_, rows) = observations(for: Self.specimen)
        #expect(!rows.contains { $0.text.contains("can't be placed in a century") })
    }

    @Test func fillerPersonalNumberCheckIsANoteAndNotACheckRow() throws {
        // The personal number has content but its check position holds a filler: the parser reports a warning
        // and no mismatch for that digit, so the screen must not say that it agrees.
        // The composite check digit is recomputed with the SDK's own function, so only the personal number's
        // check position differs from a consistent line.
        let filler = try personalNumberCheckReplacedByFiller(Self.specimen)
        let (_, rows) = observations(for: filler)
        #expect(rows.contains { $0.text == "Personal number has no check number" })
        #expect(!rows.contains { $0.text.hasPrefix("Personal number (optional) - ") })
    }

    @Test func orderIsChecksExpiryProvenanceNotesThenAdvisoryLast() {
        // A wrong document-number check digit adds the advisory; the unknown nationality adds a note.
        let broken = Self.unknownNationality.replacingOccurrences(of: "T220001293", with: "T220001294")
        let (_, rows) = observations(for: broken)
        guard let provenance = rows.firstIndex(where: { $0.text.hasPrefix("Read by") }),
              let note = rows.firstIndex(where: isUnknownCountryNote),
              let advisory = rows.firstIndex(where: { $0.text.hasPrefix("Some checks didn't agree") })
        else {
            Issue.record("expected provenance, an unknown-country note, and the advisory; got \(rows.map(\.text))")
            return
        }
        #expect(provenance < note)
        #expect(note < advisory)
        #expect(advisory == rows.count - 1)
        // Every check-digit and expiry row (non-info) precedes the provenance row.
        #expect(rows.prefix(provenance).allSatisfy { $0.tone != .info })
    }
}

/// The TD3 `text` with line 2's personal-number check digit (position 43) set to the filler, and the composite
/// check digit (position 44) recomputed over positions 1-10, 14-20 and 22-43 with the SDK's check-digit function.
private func personalNumberCheckReplacedByFiller(_ text: String) throws -> String {
    var lines = text.split(separator: "\n").map(String.init)
    let line2 = Array(lines[1])
    var body = Array(line2[0..<42]) + ["<"]
    let composite = String(body[0..<10]) + String(body[13..<20]) + String(body[21..<43])
    let digit = try CheckDigitKt.computeCheckDigit(input: composite)
    body.append(Character(Unicode.Scalar(digit)!))
    lines[1] = String(body)
    return lines.joined(separator: "\n")
}

/// The TD3 `text` with line 2's expiry date (positions 22-27) replaced by `expiry`, its check digit (position 28)
/// and the composite check digit (position 44) recomputed with the SDK's check-digit function, so the only
/// observation that changes is the one about the expiry date itself.
private func expiryReplaced(_ text: String, with expiry: String) throws -> String {
    var lines = text.split(separator: "\n").map(String.init)
    var line2 = Array(lines[1])
    line2.replaceSubrange(21..<27, with: Array(expiry))
    let expiryDigit = try CheckDigitKt.computeCheckDigit(input: expiry)
    line2[27] = Character(Unicode.Scalar(expiryDigit)!)
    let composite = String(line2[0..<10]) + String(line2[13..<20]) + String(line2[21..<43])
    let compositeDigit = try CheckDigitKt.computeCheckDigit(input: composite)
    line2[43] = Character(Unicode.Scalar(compositeDigit)!)
    lines[1] = String(line2)
    return lines.joined(separator: "\n")
}
