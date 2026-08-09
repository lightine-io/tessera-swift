import Foundation
import Tessera

// The pure, camera-free, SwiftUI-free decision layer — the iOS mirror of the Android module's decision
// functions (`routeDecode`, `reduceCameraResult`, `struggleGateAdvance`, `permissionScreenState`,
// `mapSavedImageResult`, `initialState`, `switcherMethods`, `showsMethodSwitcher`, `assembleManualDecoded`).
// Each is behaviour-preserving with its Android counterpart so both platforms make the same choices, and each
// is a free function (or a small value type) with no UI or camera dependency, host-unit-testable off-device.
//
// The honesty rules the Android reference locks in are preserved verbatim here:
//   * a `ParseResultFailure` always routes to read-failed regardless of ReviewMode (a failure is never an
//     accepted reading);
//   * a `ParseResultPartialSuccess` (check-digit mismatch) is NOT a failure — it follows the Success path
//     (review, never diverted): the UI never treats a mismatch as a failure (Principle 1);
//   * saved-image and live-camera decoding both run a single strict read (no tolerant candidate enumeration,
//     no auto-ranking or auto-picking among readings) — a picked photo either decodes or reads as empty, and
//     a live frame either confirms through consensus or the camera keeps looking.

// MARK: - Decode routing

/// Where a decoded reading routes, decided purely from the parse verdict and the configured ``ReviewMode``.
/// Mirrors the Android `DecodeRoute`.
enum DecodeRoute {
    /// The decode did not parse; show the "couldn't read" screen with the captured text.
    case showReadFailed(capturedText: RecognizedText)

    /// Instant-return: hand the decode straight back to the host as confirmed, no review step.
    case returnConfirmed(decoded: MrzScanResultDecoded)

    /// Review mode: park the decode on the review screen for the user to accept or rescan.
    case showReview(decoded: MrzScanResultDecoded)
}

/// The routing decision for a decoded reading. A `ParseResultFailure` routes to
/// ``DecodeRoute/showReadFailed(capturedText:)`` regardless of mode; otherwise ``ReviewMode/instantReturn``
/// routes to ``DecodeRoute/returnConfirmed(decoded:)`` and ``ReviewMode/review`` to
/// ``DecodeRoute/showReview(decoded:)``. A `ParseResultPartialSuccess` (check-digit mismatch) is a
/// non-failure and follows the same path as `ParseResultSuccess` — the UI never treats a mismatch as a
/// failure or diverts it (Principle 1). Mirrors the Android `routeDecode`.
func routeDecode(_ decoded: MrzScanResultDecoded, reviewMode: ReviewMode) -> DecodeRoute {
    if decoded.parse is ParseResult.Failure {
        return .showReadFailed(capturedText: decoded.recognizedText)
    }
    if reviewMode == .instantReturn {
        return .returnConfirmed(decoded: decoded)
    }
    return .showReview(decoded: decoded)
}

// MARK: - Camera result reduction

/// What one scanner result means for the flow state — the pure decision ``reduceCameraResult(_:)`` returns,
/// applied by ``ScannerModel``. Mirrors the Android `CameraFlowEffect`.
enum CameraFlowEffect {
    /// A decode is available; route it exactly as ``routeDecode(_:reviewMode:)`` decides (then the one-shot
    /// latch stops repeats).
    case goDecoded(decoded: MrzScanResultDecoded)

    /// Another app holds the camera (recoverable). Show the in-use notice; it self-resumes on the next clean frame.
    case goCameraInUse

    /// The camera cannot be started (terminal). Show the unavailable notice; no auto-recovery, no retry.
    case goCameraUnavailable

    /// A transient per-frame miss (`NoMrzFound` / `OcrFailed`) — keep scanning, no routing of its own.
    /// `sawText` is TES-97's "did OCR return any text at all on this frame" signal
    /// (`quality.recognizedLineCount > 0`): `false` for a frame with nothing recognisable in view, `true` for
    /// a frame where OCR saw text that just did not form an MRZ shape. ``ScannerModel`` folds this across the
    /// session (``struggleGateAdvance(sawTextEver:sawText:)``) to decide whether the struggle timeout is
    /// allowed to show the struggling overlay at all. Mirrors the Android `StayScanning(sawText)`.
    case stayScanning(sawText: Bool)
}

/// The flow-state decision for one `MrzScanResult` off the scanner's stream, decided purely from the result
/// kind. A `CaptureError` carrying `CameraInUse` is recoverable (the caller lets it self-resume); one
/// carrying `CameraUnavailable` is terminal; `OcrFailed` and a `NoMrzFound` keep scanning, carrying whether
/// this frame's `quality.recognizedLineCount` was non-zero (TES-97 — "OCR saw text" vs "nothing in view at
/// all"). `PermissionDenied` is not mapped to a distinct effect: the model's own permission gate owns the
/// permission path before the stream starts, so a permission-denied capture error simply keeps scanning.
/// Mirrors the Android `reduceCameraResult`.
func reduceCameraResult(_ result: MrzScanResult) -> CameraFlowEffect {
    switch result {
    case let decoded as MrzScanResultDecoded:
        return .goDecoded(decoded: decoded)
    case let noMrz as MrzScanResultNoMrzFound:
        return .stayScanning(sawText: noMrz.quality.recognizedLineCount > 0)
    case let captureError as MrzScanResultCaptureError:
        let sawText = captureError.quality.recognizedLineCount > 0
        switch captureError.error {
        case is CameraErrorCameraInUse:
            return .goCameraInUse
        case is CameraErrorCameraUnavailable:
            return .goCameraUnavailable
        case is CameraErrorOcrFailed:
            return .stayScanning(sawText: sawText)
        case is CameraErrorPermissionDenied:
            return .stayScanning(sawText: sawText)
        default:
            return .stayScanning(sawText: sawText)
        }
    default:
        return .stayScanning(sawText: false)
    }
}

/// Folds one `.stayScanning` effect into whether OCR has returned text at least once this scanning session
/// (TES-97) — an OR-fold: `sawTextEver` stays `true` once any frame carried text, regardless of later
/// text-free frames (a document that briefly leaves frame should not un-arm struggling). This is the gate
/// ``ScannerModel`` checks before showing the struggling overlay: without it, a struggle timeout with nothing
/// ever in view would show "try more light or move the document farther away" — misleading advice when there
/// was never anything to read in the first place. Pure so the "ANY, not the latest frame" semantics is
/// host-testable without a timer or camera. Mirrors the Android `struggleGateAdvance`.
func struggleGateAdvance(sawTextEver: Bool, sawText: Bool) -> Bool {
    sawTextEver || sawText
}

// MARK: - Permission screen state

/// Which face of the adaptive permission screen to show — the single decision the camera gate dispatches on.
/// Mirrors the Android `PermissionScreenState`.
enum PermissionScreenState {
    /// The camera permission is held — the gate shows the live preview, not this screen.
    case granted

    /// The permission is not held and a request can still succeed (never asked, or denied once) — mockup 04.
    case needsGrant

    /// The permission is permanently denied ("don't ask again") — only the OS settings can grant it (mockup 04b).
    case permanentlyDenied
}

/// The adaptive permission decision, decided purely from the read-only signals the gate holds:
///  * `granted` — the permission is already held → ``PermissionScreenState/granted``;
///  * `hasAsked` — whether a request has been handed out in this flow (the user tapped Grant at least once);
///  * `showRationale` — whether the platform would still show a rationale/dialog.
///
/// Once the host has been asked and the platform still won't show a rationale, the dialog won't appear again
/// → ``PermissionScreenState/permanentlyDenied``. Otherwise a request can still succeed →
/// ``PermissionScreenState/needsGrant``. Mirrors the Android `permissionScreenState`.
func permissionScreenState(granted: Bool, hasAsked: Bool, showRationale: Bool) -> PermissionScreenState {
    if granted {
        return .granted
    }
    // Asked at least once and the system won't show a rationale → the dialog won't appear again.
    if hasAsked && !showRationale {
        return .permanentlyDenied
    }
    // Never asked, or denied once (rationale true) — a request can still succeed.
    return .needsGrant
}

// MARK: - Dismiss reason (TES-115)

/// The ``DismissReason`` the global cancel (the top bar's ✕) carries — decided purely from what the user
/// was looking at when they closed (the Android `dismissReasonFor` mirror): the terminal
/// camera-unavailable screen → ``DismissReason/cameraUnavailable``; either permission screen →
/// ``DismissReason/permissionDenied``; anything else — including the recoverable in-use notice, which is
/// not terminal — ``DismissReason/userDismissed``. Reports what happened, decides nothing beyond it:
/// whether an unusable camera or an ungranted permission matters is the host's call.
func dismissReason(for state: ScannerState) -> DismissReason {
    switch state {
    case .cameraUnavailable: .cameraUnavailable
    case .permissionNeeded, .permissionPermanentlyDenied: .permissionDenied
    default: .userDismissed
    }
}

// MARK: - Saved-image outcome mapping

/// What a `SavedImageScanResult` means for the flow, decided purely from the result — the saved-image sibling
/// of ``DecodeRoute``. Mirrors the Android `SavedImageOutcome`.
enum SavedImageOutcome {
    /// The primary read decoded an MRZ — route it exactly as a camera decode would, through
    /// ``routeDecode(_:reviewMode:)`` (so a parse failure still shows the read-failed screen, a success goes
    /// to review, etc.).
    case singleDecode(decoded: MrzScanResultDecoded)

    /// No MRZ was found in the photo (or the capture step failed) — the empty screen (mockup 07b).
    case empty
}

/// Maps a `SavedImageScanResult` to the flow outcome: a `Decoded` primary scan →
/// ``SavedImageOutcome/singleDecode(decoded:)``; else → ``SavedImageOutcome/empty``. The reader is used in
/// single-read mode (`tolerant: false`, see `ScannerModel.readPickedPhoto`), so `result.candidates` is always
/// empty here — this mapping only ever sees the primary scan (there is no candidates outcome; a picked photo
/// either decodes or reads as empty, mirroring the Android saved-image flow, TES-86/TES-91). Mirrors the
/// Android `mapSavedImageResult`.
func mapSavedImageResult(_ result: SavedImageScanResult) -> SavedImageOutcome {
    if let decoded = result.scan as? MrzScanResultDecoded {
        return .singleDecode(decoded: decoded)
    }
    return .empty
}

// MARK: - Start state & method switcher

/// Where the flow starts, derived purely from the consumer's enabled methods. Preference order — camera first
/// (the default primary method), then manual entry (the always-available fallback), then saved image; an
/// empty set is treated as camera defensively. Mirrors the Android `initialState`.
func initialState(enabledMethods: Set<ScanMethod>) -> ScannerState {
    if enabledMethods.contains(.camera) {
        return .scanning(struggling: false, gathering: false)
    }
    if enabledMethods.contains(.manualEntry) {
        return .manualRaw(text: "", parseFailed: false)
    }
    if enabledMethods.contains(.savedImage) {
        return .awaitingSavedImagePick
    }
    return .scanning(struggling: false, gathering: false)
}

/// The reading methods the switcher offers, decided purely from the enabled set — only the enabled ones, in
/// the fixed display order camera, photo, type. Mirrors the Android `switcherMethods`.
func switcherMethods(enabledMethods: Set<ScanMethod>) -> [ScanMethod] {
    [.camera, .savedImage, .manualEntry].filter { enabledMethods.contains($0) }
}

/// Whether the current ``ScannerState`` is a capture / entry screen — the only screens the method switcher
/// appears on (scanning, manual raw, and the saved-image entry points). It is deliberately NOT shown on
/// outcome / gate screens, where switching method mid-outcome would be a confusing detour. Mirrors the
/// Android `showsMethodSwitcher`.
func showsMethodSwitcher(_ state: ScannerState) -> Bool {
    switch state {
    case .scanning, .manualRaw, .awaitingSavedImagePick, .savedImageEmpty:
        return true
    default:
        return false
    }
}

/// Which method the current capture / entry state belongs to, so the matching control is highlighted. Only
/// the switcher-bearing states have a method. Mirrors the Android `activeMethod`.
func activeMethod(_ state: ScannerState) -> ScanMethod? {
    switch state {
    case .scanning:
        return .camera
    case .manualRaw:
        return .manualEntry
    case .awaitingSavedImagePick, .savedImageEmpty:
        return .savedImage
    default:
        return nil
    }
}

// MARK: - Manual entry assembly

/// Splits raw typed text into the MRZ lines the reader parses: newline-separated, blank lines dropped, each
/// line trimmed of surrounding whitespace. Mirrors the Android `manualLinesOf`.
func manualLinesOf(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// Assembles an `MrzScanResultDecoded` from the raw text a user typed, running `ManualMrzReader`'s auto-detect
/// entry point over the split lines and wrapping the parser's verdict together with the typed lines as the
/// recognized text. The reader stamps `ReadMethod.MANUAL_ENTRY` as provenance, so the resulting `Decoded`
/// carries manual-entry provenance through unchanged. A garbage or malformed input yields a `Decoded` whose
/// `parse` is a `ParseResultFailure`, which routes to the read-failed screen exactly as a failed camera
/// decode does (reader, not oracle: manual entry adds no judgement of its own). Mirrors the Android
/// `assembleManualDecoded`.
///
/// - Note: Android splits the text into lines and calls the pre-split `List<String>` reader overloads; this
///   mirrors that (the `input:referenceTime_:` array overloads), so the auto-detect / format-specific
///   behaviour matches line-for-line.
func assembleManualDecoded(
    text: String,
    referenceTime: KotlinInstant = nowInstant()
) -> MrzScanResultDecoded {
    let lines = manualLinesOf(text)
    // Format always auto-detected from the line count and per-line lengths (TES-100 — the Auto/Passport/
    // ID-card hint picker is gone on both platforms; a hint never changed the input, only the parser).
    let parse = ManualMrzReader.shared.read(input: lines, referenceTime_: referenceTime)
    return MrzScanResultDecoded(
        parse: parse,
        recognizedText: RecognizedText(lines: lines.map { RecognizedLine(text: $0, confidence: nil) }),
        quality: ScanQuality(
            mrzRegionFound: true,
            ocrConfidence: nil,
            recognizedLineCount: Int32(lines.count)
        )
    )
}

// MARK: - Session scan deadline (TES-124/125/126)

/// The session-level scan-timeout deadline's pure accumulator — the iOS mirror of the Android
/// `rememberScanDeadline`'s accumulation math, extracted as a value type so the drift-corrected
/// advance-and-fire logic is host-testable without a real clock, timer, or scene-phase observer.
/// ``ScannerModel`` owns one instance and feeds it the REAL elapsed *active* time between ticks (measured
/// against a monotonic `ContinuousClock`, never wall-clock `Date` — a clock change, DST, or NTP correction
/// must never perturb the deadline). Pausing/resuming while backgrounded needs no special-case here: the
/// caller simply stops calling ``advance(by:)`` while backgrounded, and the accumulated total already carries
/// the pause forward, exactly like the Android `repeatOnLifecycle(RESUMED)` gate resuming from the saved
/// `accumulatedMs` rather than restarting.
struct DeadlineClock {
    /// The total session budget.
    let total: Duration

    /// The active time accumulated so far, clamped to `[0, total]`.
    private(set) var accumulated: Duration = .zero

    /// One-shot latch: once `true`, further ``advance(by:)`` calls are no-ops. Mirrors the Android `fired`.
    private(set) var fired = false

    init(total: Duration) {
        self.total = total
    }

    /// The time left, clamped to `[0, total]` — what the countdown chip shows (via ``formatCountdown(_:)``).
    var remaining: Duration {
        max(.zero, total - accumulated)
    }

    /// Advances the accumulator by `elapsed` (clamped so it never exceeds `total`). Returns `true` exactly
    /// once — on the call that first reaches the total — so the caller fires its one-shot "give up" effect
    /// only once, never on a later tick. A no-op (always returns `false`) once already fired.
    @discardableResult
    mutating func advance(by elapsed: Duration) -> Bool {
        guard !fired else { return false }
        accumulated = min(total, accumulated + elapsed)
        guard accumulated >= total else { return false }
        fired = true
        return true
    }
}

/// Formats a countdown `Duration` as `M:SS` (minutes:seconds, seconds zero-padded) — the shape the
/// scan-countdown chip shows. Seconds are rounded **up** so the chip reads `0:01` through the final second
/// and only shows `0:00` at true expiry; a negative input (should not occur — the caller clamps at zero, via
/// ``DeadlineClock/remaining``) also clamps to `0:00`. Minutes are not capped at two digits (a multi-minute
/// host `scanTimeout` renders e.g. `10:00`). Digits only — no `String(format:)`, matching the module's
/// established positional-substitution style (see `Localization.swift`) rather than a locale-sensitive
/// formatter. Pure, so it is host-tested. Mirrors the Android `formatCountdown`.
func formatCountdown(_ remaining: Duration) -> String {
    let seconds = remaining.components.seconds
    let attoseconds = remaining.components.attoseconds
    guard seconds > 0 || (seconds == 0 && attoseconds > 0) else { return "0:00" }
    let totalSeconds = attoseconds > 0 ? seconds + 1 : seconds
    let minutes = totalSeconds / 60
    let secs = totalSeconds % 60
    let secsString = secs < 10 ? "0\(secs)" : "\(secs)"
    return "\(minutes):\(secsString)"
}

// MARK: - VoiceOver announce-on-arrival (TES-58)

/// The VoiceOver announcement key to post when the flow transitions INTO `state`, or `nil` when the state
/// carries none — the iOS mirror of the Android live-region placements across `ReviewScreen.kt`
/// (`ReviewContent`/`ReadFailedContent`), `CameraStatusScreen.kt` (`CameraInUseContent`/
/// `CameraUnavailableContent`), and `SavedImageScreen.kt` (`SavedImageAnalyzingContent`/
/// `SavedImageEmptyContent`). Android splits these into ASSERTIVE (review, read-failed, camera-unavailable,
/// saved-image-empty — decode/terminal landings the user must hear right away) and POLITE (camera-in-use,
/// saved-image-analyzing — auto-transitions with no urgency). `UIAccessibility`'s `.announcement` notification
/// has no polite/assertive tier, so both groups are posted identically by the caller — a plain announcement,
/// immediately on arrival.
///
/// Every other state carries no announcement of its own here: the struggling/gathering scanning overlays are
/// a rising-edge flag on `.scanning`, not a distinct case, so ``ScannerModel`` announces those directly at
/// the point they flip on, rather than through this state-keyed mapping. Pure and UIKit-free, so the mapping
/// is host-testable without posting a real accessibility notification.
func announcementKey(for state: ScannerState) -> String? {
    switch state {
    case .review:
        return "tessera_scanner_review_title"
    case .readFailed:
        return "tessera_scanner_read_failed_title"
    case .cameraUnavailable:
        return "tessera_scanner_camera_unavailable_title"
    case .savedImageEmpty:
        return "tessera_scanner_saved_image_empty_title"
    case .cameraInUse:
        return "tessera_scanner_camera_in_use_title"
    case .savedImageAnalyzing:
        return "tessera_scanner_saved_image_analyzing_title"
    default:
        return nil
    }
}

// MARK: - Field label decisions

/// Which `tessera_scanner_field_optional*` / `tessera_scanner_check_label_optional_data` localization key
/// names the format-specific optional/personal-data field: TD3 carries ICAO's real "personal number" concept
/// (the SAME label reused for both the field row and its check-digit observation); every other format's MRZ
/// optional data has no such meaning, so it gets a neutral label instead — and the field row and the
/// check-digit observation use two DIFFERENT neutral keys there (`forCheckDigit` selects which), matching the
/// Android source's own two distinct resources for the same non-TD3 concept. Pure so the choice is
/// host-testable without a document. Mirrors the Android `reviewAllFieldRows` / `parseObservations`
/// `if (document is TD3) ... else ...` branches (`ReviewScreen.kt:160-164` / `255-257`).
func optionalFieldLabelKey(isTD3: Bool, forCheckDigit: Bool) -> String {
    if isTD3 { return "tessera_scanner_field_optional" }
    return forCheckDigit ? "tessera_scanner_check_label_optional_data" : "tessera_scanner_field_optional_data"
}

// MARK: - Single live-preview guidance message (TES-95/TES-129)

/// The ONE guidance message the live-preview overlay shows below the framing-guide box — the iOS mirror of
/// the Android `MrzGuideOverlay`'s single guidance region (`MrzScannerScreen.kt:1595-1694`). Exactly one of
/// these ever renders at a time.
enum GuidanceMessage: Equatable {
    /// The frame-agreement consensus gate is confirming a read across several frames — "Hold steady…".
    case gathering

    /// No decode for a while — the "still looking / type it instead" nudge.
    case struggling

    /// Nothing else to show — the plain "line up the document" framing hint.
    case framingHint
}

/// The guidance-message precedence: `gathering` beats `struggling` beats the plain framing hint — getting a
/// decode at all (gathering) is better news than "still looking" (struggling), and either supersedes the
/// baseline hint. Pure so the precedence itself is host-testable with no view or camera. Mirrors the Android
/// `MrzGuideOverlay`'s `when { gathering -> ...; struggling -> ...; else -> ... }`.
func guidanceMessage(gathering: Bool, struggling: Bool) -> GuidanceMessage {
    if gathering { return .gathering }
    if struggling { return .struggling }
    return .framingHint
}

// MARK: - Time bridge

/// The current instant as a Kotlin `Instant`, for the date-window inference the manual reader does. The K/N
/// framework does not export `Clock.System.now()` (it is marked unavailable), so the moment is taken from
/// Swift's `Date` and rebuilt via the `Instant.Companion.fromEpochMilliseconds` factory — the same wall-clock
/// "now" the Android path gets from `Clock.System.now()`.
func nowInstant() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(
        epochMilliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded())
    )
}
