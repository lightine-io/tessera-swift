import Testing
import Tessera
@testable import TesseraUI

/// TES-152: the review screen states the parser's warnings as neutral notes. Observations only (reader, not
/// oracle): never a verdict, never blocking. Fixtures are the ICAO Doc 9303 published TD3 specimen
/// (fictional Utopia), with the nationality code swapped for one that is not in the SDK's country table.
@MainActor
struct ReviewWarningObservationsTests {
    private static let specimen = """
    P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
    L898902C36UTO7408122F1204159ZE184226B<<<<<10
    """
    // Nationality (line 2, positions 11-13) is outside every check digit, so only the country code changes.
    private static let unknownNationality = specimen.replacingOccurrences(of: "C36UTO7408122", with: "C36XQZ7408122")

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
        // Info rows are: provenance, one note per mapped warning, and the mismatch advisory (absent here).
        let (decoded, rows) = observations(for: Self.specimen)
        let infoCount = rows.filter { $0.tone == .info }.count
        #expect(infoCount == 1 + decoded.parse.metadata.warnings.count)
    }

    @Test func fillerPersonalNumberCheckIsANoteAndNotACheckRow() {
        // The personal number has content but its check position holds a filler: the parser reports a warning
        // and no mismatch for that digit, so the screen must not say that it agrees.
        let filler = Self.specimen.replacingOccurrences(of: "B<<<<<10", with: "B<<<<<<0")
        let (_, rows) = observations(for: filler)
        #expect(rows.contains { $0.text == "Personal number has no check number" })
        #expect(!rows.contains { $0.text.hasPrefix("Personal number (optional) - ") })
    }

    @Test func orderIsChecksExpiryProvenanceNotesThenAdvisoryLast() {
        // A wrong document-number check digit adds the advisory; the unknown nationality adds a note.
        let broken = Self.unknownNationality.replacingOccurrences(of: "L898902C36", with: "L898902C37")
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
