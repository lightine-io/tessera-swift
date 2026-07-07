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
        let decoded = assembleManualDecoded(text: "not an mrz at all", hint: .auto)
        #expect(decoded.parse is ParseResult.Failure) // precondition
        for mode in [ReviewMode.review, .instantReturn] {
            if case .showReadFailed = routeDecode(decoded, reviewMode: mode) { } else {
                Issue.record("a parse failure must route to read-failed in mode \(mode)")
            }
        }
    }

    @Test func nonFailureRoutesToReviewOrInstantReturn() {
        let decoded = assembleManualDecoded(text: Self.icaoTD3, hint: .passport)
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

        let decoded = assembleManualDecoded(text: "x", hint: .auto)
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
        #expect(showsMethodSwitcher(.scanning(struggling: false)))
        #expect(showsMethodSwitcher(.manualRaw(text: "")))
        #expect(showsMethodSwitcher(.awaitingSavedImagePick))
        #expect(showsMethodSwitcher(.savedImageEmpty))
        // Not on outcome / gate screens.
        #expect(!showsMethodSwitcher(.readFailed(capturedText: RecognizedText(lines: []))))
        #expect(!showsMethodSwitcher(.cameraUnavailable))
        #expect(!showsMethodSwitcher(.permissionNeeded))
    }
}
