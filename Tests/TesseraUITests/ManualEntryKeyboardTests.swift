import Testing
@testable import TesseraUI

/// TES-239: closing the manual-entry keyboard keeps the typed text and starts no read (the TES-154 rule).
///
/// The screen owns two dismissal controls, the Done button above the keyboard and a tap outside the field.
/// Both call ``ManualEntryScreen/dismissKeyboard()``. The third way, scrolling, is the system's
/// `scrollDismissesKeyboard` and runs no code of this screen. So the rule holds when that one handler calls
/// neither callback: the text lives in the model and only `onTextChange` can change it, and only `onRead`
/// starts a read. These tests do not drive the gestures themselves; the package has no UI test host.
@MainActor
struct ManualEntryKeyboardTests {
    /// Counts the callbacks a ``ManualEntryScreen`` makes.
    private final class Calls {
        var textChanges: [String] = []
        var reads = 0
    }

    // The typed text is the first line of the published ICAO Doc 9303 TD3 specimen.
    private static let typed = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"

    private func makeScreen(_ calls: Calls) -> ManualEntryScreen {
        ManualEntryScreen(
            text: Self.typed,
            parseFailed: false,
            onTextChange: { calls.textChanges.append($0) },
            onRead: { calls.reads += 1 }
        )
    }

    @Test func dismissingTheKeyboardStartsNoRead() {
        let calls = Calls()
        makeScreen(calls).dismissKeyboard()
        #expect(calls.reads == 0)
    }

    @Test func dismissingTheKeyboardLeavesTheTypedTextAlone() {
        let calls = Calls()
        makeScreen(calls).dismissKeyboard()
        #expect(calls.textChanges.isEmpty)
    }

    @Test func dismissingTheKeyboardLeavesTheModelDraftAndStateAlone() {
        // The same rule one level down: with the screen wired to a real model, as RootScannerView wires it,
        // a dismissal leaves the draft in `.manualRaw` unchanged and does not route to a review.
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        model.updateManualText(Self.typed)
        let screen = ManualEntryScreen(
            text: Self.typed,
            parseFailed: false,
            onTextChange: { model.updateManualText($0) },
            onRead: { model.readManual(text: Self.typed) }
        )

        screen.dismissKeyboard()

        if case let .manualRaw(text, parseFailed, _) = model.state {
            #expect(text == Self.typed)
            #expect(parseFailed == false)
        } else {
            Issue.record("a keyboard dismissal must leave the model in .manualRaw; got \(model.state)")
        }
    }
}
