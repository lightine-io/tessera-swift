import Testing
import Tessera
@testable import TesseraUI

/// Host tests for the pure decision layer — the iOS mirror of the Android module's decision-function tests.
/// These lock in the honesty rules (Principle 1) that must hold identically on both platforms. The full
/// field/observation *rendering* is exercised by the Android host tests (same logic) and by on-device
/// verification; here we test the pure routing/mapping decisions that need no UI.
struct ScannerDecisionsTests {
    // The ICAO Doc 9303 published TD3 specimen (country "UTO" = fictional Utopia) — a permitted test vector,
    // not real document data. Used to get a non-failure parse for the review-routing path.
    private static let icaoTD3 = """
    P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
    L898902C36UTO7408122F1204159ZE184226B<<<<<10
    """

    private func quality() -> ScanQuality {
        ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 0)
    }

    // MARK: routeDecode — the honesty-critical routing

    @Test func failureRoutesToReadFailedRegardlessOfMode() {
        let decoded = assembleManualDecoded(text: "not an mrz at all")
        #expect(decoded.parse is ParseResult.Failure) // precondition
        for mode in [ReviewMode.review, .instantReturn] {
            if case .showReadFailed = routeDecode(decoded, reviewMode: mode) { } else {
                Issue.record("a parse failure must route to read-failed in mode \(mode)")
            }
        }
    }

    @Test func nonFailureRoutesToReviewOrInstantReturn() {
        let decoded = assembleManualDecoded(text: Self.icaoTD3)
        #expect(!(decoded.parse is ParseResult.Failure)) // Success or PartialSuccess — a non-failure
        if case .showReview = routeDecode(decoded, reviewMode: .review) { } else {
            Issue.record("review mode must park a non-failure decode on review")
        }
        if case .returnConfirmed = routeDecode(decoded, reviewMode: .instantReturn) { } else {
            Issue.record("instant-return must hand a non-failure decode straight back")
        }
    }

    // MARK: reduceCameraResult — per-frame effect mapping

    @Test func cameraResultsReduceToTheRightEffect() {
        let inUse = MrzScanResultCaptureError(error: CameraErrorCameraInUse(message: "x"), quality: quality())
        if case .goCameraInUse = reduceCameraResult(inUse) { } else { Issue.record("in-use → goCameraInUse") }

        let unavailable = MrzScanResultCaptureError(error: CameraErrorCameraUnavailable(message: "x"), quality: quality())
        if case .goCameraUnavailable = reduceCameraResult(unavailable) { } else { Issue.record("unavailable → goCameraUnavailable") }

        let ocrFailed = MrzScanResultCaptureError(error: CameraErrorOcrFailed(message: "x"), quality: quality())
        if case .stayScanning = reduceCameraResult(ocrFailed) { } else { Issue.record("ocr-failed is transient → stayScanning") }

        let noMrz = MrzScanResultNoMrzFound(recognizedText: RecognizedText(lines: []), quality: quality())
        if case .stayScanning = reduceCameraResult(noMrz) { } else { Issue.record("no-mrz → stayScanning") }

        let decoded = assembleManualDecoded(text: "x")
        if case .goDecoded = reduceCameraResult(decoded) { } else { Issue.record("a decode → goDecoded") }
    }

    // MARK: permissionScreenState

    @Test func permissionStateFollowsTheThreeSignals() {
        #expect(permissionScreenState(granted: true, hasAsked: false, showRationale: false) == .granted)
        #expect(permissionScreenState(granted: false, hasAsked: false, showRationale: false) == .needsGrant)
        #expect(permissionScreenState(granted: false, hasAsked: true, showRationale: false) == .permanentlyDenied)
        // Denied once but the platform would still show a rationale — a request can still succeed.
        #expect(permissionScreenState(granted: false, hasAsked: true, showRationale: true) == .needsGrant)
    }

    // MARK: start state & switcher

    @Test func initialStatePrefersCameraThenManualThenSavedImage() {
        if case .scanning = initialState(enabledMethods: [.camera, .manualEntry, .savedImage]) { } else { Issue.record("camera first") }
        if case .manualRaw = initialState(enabledMethods: [.manualEntry, .savedImage]) { } else { Issue.record("manual next") }
        if case .awaitingSavedImagePick = initialState(enabledMethods: [.savedImage]) { } else { Issue.record("saved-image last") }
        if case .scanning = initialState(enabledMethods: []) { } else { Issue.record("empty defaults to camera") }
    }

    @Test func switcherShowsOnlyEnabledMethodsInFixedOrder() {
        #expect(switcherMethods(enabledMethods: [.manualEntry, .camera]) == [.camera, .manualEntry])
        #expect(switcherMethods(enabledMethods: [.savedImage, .camera, .manualEntry]) == [.camera, .savedImage, .manualEntry])
        #expect(switcherMethods(enabledMethods: [.savedImage]) == [.savedImage])
    }

    @Test func switcherShowsOnCaptureAndEntryScreensOnly() {
        #expect(showsMethodSwitcher(.scanning(struggling: false, gathering: false)))
        #expect(showsMethodSwitcher(.manualRaw(text: "", parseFailed: false)))
        #expect(showsMethodSwitcher(.awaitingSavedImagePick))
        #expect(showsMethodSwitcher(.savedImageEmpty))
        // Not on outcome / gate screens.
        #expect(!showsMethodSwitcher(.readFailed(capturedText: RecognizedText(lines: []))))
        #expect(!showsMethodSwitcher(.cameraUnavailable))
        #expect(!showsMethodSwitcher(.permissionNeeded))
    }

    // MARK: struggleGateAdvance — TES-97 struggle-gate fold

    /// An OR-fold: once any frame carried text, `sawTextEver` stays `true` regardless of later text-free
    /// frames (a document that briefly leaves frame must not un-arm the struggling overlay).
    @Test func struggleGateAdvanceIsAnOrFoldThatNeverUnLatches() {
        #expect(struggleGateAdvance(sawTextEver: false, sawText: false) == false)
        #expect(struggleGateAdvance(sawTextEver: false, sawText: true) == true)
        #expect(struggleGateAdvance(sawTextEver: true, sawText: false) == true)
        #expect(struggleGateAdvance(sawTextEver: true, sawText: true) == true)
    }

    // MARK: reduceCameraResult — TES-97 sawText propagation

    /// `stayScanning`'s `sawText` mirrors `quality.recognizedLineCount > 0` for both the transient-miss
    /// result kinds it covers — a `NoMrzFound` and a `CaptureError(OcrFailed)` frame.
    @Test func stayScanningCarriesWhetherOcrSawTextOnTheFrame() {
        let textyQuality = ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 2)
        let emptyQuality = quality() // recognizedLineCount: 0

        let noMrzWithText = MrzScanResultNoMrzFound(recognizedText: RecognizedText(lines: []), quality: textyQuality)
        guard case let .stayScanning(sawText) = reduceCameraResult(noMrzWithText) else {
            Issue.record("no-mrz must stayScanning"); return
        }
        #expect(sawText)

        let noMrzEmpty = MrzScanResultNoMrzFound(recognizedText: RecognizedText(lines: []), quality: emptyQuality)
        guard case let .stayScanning(sawTextEmpty) = reduceCameraResult(noMrzEmpty) else {
            Issue.record("no-mrz must stayScanning"); return
        }
        #expect(!sawTextEmpty)

        let ocrFailedWithText = MrzScanResultCaptureError(error: CameraErrorOcrFailed(message: "x"), quality: textyQuality)
        guard case let .stayScanning(sawTextOcr) = reduceCameraResult(ocrFailedWithText) else {
            Issue.record("ocr-failed must stayScanning"); return
        }
        #expect(sawTextOcr)
    }

    // MARK: mapSavedImageResult — single-read saved image (TES-86/TES-91)

    /// A `Decoded` primary scan always maps to `singleDecode`, even when `candidates` is non-empty — the
    /// reader runs in single-read mode (`tolerant: false`), so `mapSavedImageResult` no longer inspects
    /// `candidates` at all; there is no candidates outcome to route to any more.
    @Test func savedImageMapsToSingleDecodeIgnoringAnyCandidates() {
        let decoded = assembleManualDecoded(text: Self.icaoTD3)
        let candidate = MrzCandidate(mrzLines: [], parse: decoded.parse, disambiguations: [])
        let result = SavedImageScanResult(scan: decoded, candidates: [candidate], captureMetadata: nil)
        guard case let .singleDecode(mapped) = mapSavedImageResult(result) else {
            Issue.record("a Decoded scan must map to singleDecode even with non-empty candidates")
            return
        }
        #expect(mapped === decoded)
    }

    @Test func savedImageMapsToEmptyWhenNothingWasFound() {
        let noMrz = MrzScanResultNoMrzFound(recognizedText: RecognizedText(lines: []), quality: quality())
        let result = SavedImageScanResult(scan: noMrz, candidates: [], captureMetadata: nil)
        if case .empty = mapSavedImageResult(result) { } else {
            Issue.record("a NoMrzFound scan must map to empty")
        }
    }

    // MARK: MrzDecodeConsensus wiring — the live consensus gate (TES-91)

    /// `MrzDecodeConsensus` itself is camera-free and pure, so its ``ScannerModel`` wiring (the `is
    /// ConsensusVerdictConfirmed` / `is ConsensusVerdictGathering` dispatch) is host-testable directly:
    /// below `threshold` agreeing frames it reports `Gathering` (the "hold steady" cue), and at `threshold`
    /// it confirms exactly once.
    @Test func consensusGathersThenConfirmsAcrossAgreeingFrames() {
        let consensus = MrzDecodeConsensus(threshold: 2)
        let decoded = assembleManualDecoded(text: Self.icaoTD3)

        guard let gathering = consensus.offer(decoded: decoded) as? ConsensusVerdictGathering else {
            Issue.record("the first agreeing frame must gather, not confirm, at threshold 2")
            return
        }
        #expect(gathering.agreement == 1)
        #expect(gathering.threshold == 2)

        guard let confirmed = consensus.offer(decoded: decoded) as? ConsensusVerdictConfirmed else {
            Issue.record("the second agreeing frame must confirm at threshold 2")
            return
        }
        #expect(!(confirmed.decoded.parse is ParseResult.Failure))
    }

    /// `reset()` clears the tally — the iOS mirror of ``ScannerModel/resetLiveSessionGates()`` re-arming the
    /// gate on a fresh live session, so a prior session's votes never carry over.
    @Test func consensusResetClearsThePriorTally() {
        let consensus = MrzDecodeConsensus(threshold: 2)
        let decoded = assembleManualDecoded(text: Self.icaoTD3)
        _ = consensus.offer(decoded: decoded) // one vote cast
        consensus.reset()
        guard let gathering = consensus.offer(decoded: decoded) as? ConsensusVerdictGathering else {
            Issue.record("after reset the tally must restart from zero, not confirm on the first re-offer")
            return
        }
        #expect(gathering.agreement == 1)
    }

    // MARK: inline manual parse-fail (TES-93) — the assembleManualDecoded precondition

    /// ``ScannerModel/readManual(text:)`` inlines the "stay on manual entry with a parseFailed note vs.
    /// route through ``routeDecode(_:reviewMode:)``" branch itself (mirroring the Android `ManualRaw` `onRead`
    /// branch, itself inlined in `ScannerBody` rather than a separate top-level function) — so there is no
    /// separate pure function to test that branch at this layer. What IS pure and host-testable is the
    /// precondition it switches on: garbage typed text still assembles to a `ParseResult.Failure`, exactly as
    /// it does for the read-failed routing path above.
    @Test func manualParseFailurePreconditionStillHoldsForGarbageInput() {
        let decoded = assembleManualDecoded(text: "not an mrz at all")
        #expect(decoded.parse is ParseResult.Failure)
    }

    // MARK: formatCountdown — TES-125 countdown-chip formatting

    /// Seconds round UP (never down) and are zero-padded; minutes are never capped at two digits.
    @Test func formatCountdownRoundsSecondsUpAndPadsToTwoDigits() {
        #expect(formatCountdown(.seconds(90)) == "1:30")
        // 4.5s must ceil to 5s (0:05), not floor to 0:04 — the chip reads "0:05" through the whole last second.
        #expect(formatCountdown(.milliseconds(4500)) == "0:05")
        #expect(formatCountdown(.zero) == "0:00")
        // A multi-minute scanTimeout is not capped at two digits.
        #expect(formatCountdown(.seconds(600)) == "10:00")
    }

    /// A negative input (should not occur — the caller clamps via `DeadlineClock.remaining`) still clamps to
    /// `0:00` defensively, mirroring the Android `coerceAtLeast(0L)`.
    @Test func formatCountdownClampsNegativeToZero() {
        #expect(formatCountdown(.seconds(-5)) == "0:00")
    }

    // MARK: DeadlineClock — TES-124/126 session-deadline accumulation

    /// Accumulates active elapsed time across ticks and fires exactly once — on the tick that first reaches
    /// the total — never again on a later tick.
    @Test func deadlineClockAccumulatesAndFiresExactlyOnceAtTheTotal() {
        var clock = DeadlineClock(total: .seconds(2))
        #expect(clock.remaining == .seconds(2))
        let first = clock.advance(by: .seconds(1))
        #expect(!first)
        #expect(clock.remaining == .seconds(1))
        #expect(!clock.fired)

        let second = clock.advance(by: .seconds(1)) // this tick reaches the total — fires
        #expect(second)
        #expect(clock.fired)
        #expect(clock.remaining == .zero)

        // A further advance after firing is a no-op — the one-shot latch never fires twice.
        let third = clock.advance(by: .seconds(5))
        #expect(!third)
        #expect(clock.fired)
        #expect(clock.remaining == .zero)
    }

    /// A single tick that overshoots the total (e.g. a scheduler hiccup) still clamps the accumulator at the
    /// total and fires exactly once, rather than accumulating past it.
    @Test func deadlineClockClampsAccumulatedAtTheTotalOnAnOvershootingTick() {
        var clock = DeadlineClock(total: .seconds(2))
        let fired = clock.advance(by: .seconds(10))
        #expect(fired)
        #expect(clock.remaining == .zero)
        #expect(clock.fired)
    }

    // MARK: announcementKey — TES-58 VoiceOver announce-on-arrival mapping

    /// Exactly the six outcome states carry an announcement (mirroring the Android live-region set); every
    /// other state — the scanning overlays included, which are announced separately by `ScannerModel` on
    /// their own rising edge — maps to `nil`.
    @Test func announcementKeyMapsTheSixOutcomeStatesAndNothingElse() {
        let decoded = assembleManualDecoded(text: Self.icaoTD3)
        #expect(announcementKey(for: .review(decoded: decoded, expanded: false, source: .camera)) == "tessera_scanner_review_title")
        #expect(announcementKey(for: .readFailed(capturedText: RecognizedText(lines: []))) == "tessera_scanner_read_failed_title")
        #expect(announcementKey(for: .cameraUnavailable) == "tessera_scanner_camera_unavailable_title")
        #expect(announcementKey(for: .savedImageEmpty) == "tessera_scanner_saved_image_empty_title")
        #expect(announcementKey(for: .cameraInUse) == "tessera_scanner_camera_in_use_title")
        #expect(announcementKey(for: .savedImageAnalyzing) == "tessera_scanner_saved_image_analyzing_title")

        // Every other state carries no announcement of its own.
        #expect(announcementKey(for: .scanning(struggling: false, gathering: false)) == nil)
        #expect(announcementKey(for: .scanning(struggling: true, gathering: true)) == nil)
        #expect(announcementKey(for: .manualRaw(text: "", parseFailed: false)) == nil)
        #expect(announcementKey(for: .awaitingSavedImagePick) == nil)
        #expect(announcementKey(for: .permissionNeeded) == nil)
        #expect(announcementKey(for: .permissionPermanentlyDenied) == nil)
    }

    // MARK: withoutTrailingFiller — TES-129 item 8, display-only trailing-'<' stripping

    /// Trailing MRZ filler (`<`) is stripped for display; interior fillers and non-filler content are left
    /// alone — mirrors the Android `String.withoutTrailingFiller` (`trimEnd('<')`).
    @Test func withoutTrailingFillerStripsOnlyTrailingFillerCharacters() {
        #expect(withoutTrailingFiller("L898902C<") == "L898902C")
        #expect(withoutTrailingFiller("L898902C<<<<") == "L898902C")
        #expect(withoutTrailingFiller("L898902C") == "L898902C")
        // Interior '<' (a real MRZ separator, e.g. between name components) is not a trailing filler.
        #expect(withoutTrailingFiller("ERIKSSON<<ANNA") == "ERIKSSON<<ANNA")
        // All-filler collapses to empty, matching Android's "no row at all" blank check downstream.
        #expect(withoutTrailingFiller("<<<<<") == "")
        #expect(withoutTrailingFiller("") == "")
    }

    // MARK: optionalFieldLabelKey — TES-129 item 3, per-format optional-data label

    /// TD3 always gets the "personal number" label — the SAME key for both the field row and the check-digit
    /// observation. Every other format gets a neutral label, but a DIFFERENT key per context (the field row
    /// vs. the check-digit observation), matching the two distinct Android resources for that one concept.
    @Test func optionalFieldLabelKeyPicksPersonalNumberOnlyForTD3() {
        #expect(optionalFieldLabelKey(isTD3: true, forCheckDigit: false) == "tessera_scanner_field_optional")
        #expect(optionalFieldLabelKey(isTD3: true, forCheckDigit: true) == "tessera_scanner_field_optional")
        #expect(optionalFieldLabelKey(isTD3: false, forCheckDigit: false) == "tessera_scanner_field_optional_data")
        #expect(optionalFieldLabelKey(isTD3: false, forCheckDigit: true) == "tessera_scanner_check_label_optional_data")
    }

    // MARK: guidanceMessage — TES-129 item 6, single live-preview guidance precedence

    /// Exactly one guidance message at a time: gathering beats struggling beats the plain framing hint.
    @Test func guidanceMessagePrecedenceIsGatheringThenStrugglingThenFramingHint() {
        #expect(guidanceMessage(gathering: true, struggling: true) == .gathering)
        #expect(guidanceMessage(gathering: true, struggling: false) == .gathering)
        #expect(guidanceMessage(gathering: false, struggling: true) == .struggling)
        #expect(guidanceMessage(gathering: false, struggling: false) == .framingHint)
    }

    // MARK: dismissReason — TES-115, the Android dismissReasonFor mirror

    @Test func dismissReasonIsCameraUnavailableOnlyFromTheTerminalCameraErrorScreen() {
        #expect(dismissReason(for: .cameraUnavailable) == .cameraUnavailable)
        // The in-use notice is recoverable, not terminal — a close from it is a plain dismissal.
        #expect(dismissReason(for: .cameraInUse) == .userDismissed)
    }

    @Test func dismissReasonIsPermissionDeniedFromEitherPermissionScreen() {
        #expect(dismissReason(for: .permissionNeeded) == .permissionDenied)
        #expect(dismissReason(for: .permissionPermanentlyDenied) == .permissionDenied)
    }

    @Test func dismissReasonIsUserDismissedEverywhereElse() {
        #expect(dismissReason(for: .scanning(struggling: false, gathering: false)) == .userDismissed)
        #expect(dismissReason(for: .manualRaw(text: "", parseFailed: false)) == .userDismissed)
        #expect(dismissReason(for: .awaitingSavedImagePick) == .userDismissed)
        #expect(dismissReason(for: .savedImageEmpty) == .userDismissed)
    }
}
