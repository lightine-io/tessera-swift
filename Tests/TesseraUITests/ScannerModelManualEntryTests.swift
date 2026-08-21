import Testing
@testable import TesseraUI

/// Host tests for ``ScannerModel/updateManualText(_:)`` — TES-137's cap on the manual-entry draft length,
/// the iOS mirror of the Android `MANUAL_ENTRY_MAX_CHARS` cap (`ManualEntryScreen.kt` /
/// `ScannerUiStateSaverTest.kt`). Runs on the main actor since ``ScannerModel`` is `@MainActor`.
@MainActor
struct ScannerModelManualEntryTests {
    private func makeModel() -> ScannerModel {
        ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
    }

    @Test func typingWithinTheCapIsNotTruncated() {
        let model = makeModel()
        let text = "P<UTOERIKSSON<<ANNA<MARIA"
        model.updateManualText(text)

        if case let .manualRaw(stateText, parseFailed) = model.state {
            #expect(stateText == text)
            #expect(parseFailed == false)
        } else {
            Issue.record("updateManualText must transition to .manualRaw")
        }
    }

    @Test func typingPastTheCapLeavesTheDraftAtExactlyMaxChars() {
        // TES-137: a paste far past the cap must truncate, never reject and never overflow past it. Garbage
        // repeats of a single character, well past any real MRZ — never real document data.
        let model = makeModel()
        let pasted = String(repeating: "A", count: 1524)
        model.updateManualText(pasted)

        if case let .manualRaw(stateText, _) = model.state {
            #expect(stateText.count == 1024, "the draft must truncate to exactly 1024 characters, not reject or overflow past it")
        } else {
            Issue.record("updateManualText must transition to .manualRaw")
        }
    }

    @Test func aParseFailedNoteIsClearedOnEveryEditIncludingATruncatedOne() {
        let model = makeModel()
        let pasted = String(repeating: "B", count: 2000)
        model.updateManualText(pasted)

        if case let .manualRaw(_, parseFailed) = model.state {
            #expect(parseFailed == false, "any edit — truncated or not — clears a prior parse-failed note")
        } else {
            Issue.record("updateManualText must transition to .manualRaw")
        }
    }
}
