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

/// Which parser ``assembleManualDecoded(text:hint:referenceTime:)`` runs against the typed lines — a *hint*,
/// not a transformation. The choice selects the `ManualMrzReader` entry point; it never touches the input the
/// user typed (reader, not oracle, Principle 1). `expectedLineLength` is the per-line character count the
/// format expects, or `nil` for ``auto``. Mirrors the Android `ManualFormatHint`.
enum ManualFormatHint {
    /// Auto-detect the format from the line count and per-line lengths (`ManualMrzReader.read`).
    case auto

    /// Parse as TD3 (passport): 2 lines × 44 (`ManualMrzReader.readTD3`).
    case passport

    /// Parse as TD1 (identity card): 3 lines × 30 (`ManualMrzReader.readTD1`).
    case idCard

    /// The per-line character count the format expects, or `nil` for ``auto`` (no single expected length).
    var expectedLineLength: Int? {
        switch self {
        case .auto: return nil
        case .passport: return Int(Td3FormatSpec().lineLength)
        case .idCard: return Int(Td1FormatSpec().lineLength)
        }
    }
}

/// Splits raw typed text into the MRZ lines the reader parses: newline-separated, blank lines dropped, each
/// line trimmed of surrounding whitespace. Mirrors the Android `manualLinesOf`.
func manualLinesOf(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// Assembles an `MrzScanResultDecoded` from the raw text a user typed, running the `hint`'s `ManualMrzReader`
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
    hint: ManualFormatHint,
    referenceTime: KotlinInstant = nowInstant()
) -> MrzScanResultDecoded {
    let lines = manualLinesOf(text)
    let reader = ManualMrzReader.shared
    let parse: ParseResult
    switch hint {
    case .auto:
        parse = reader.read(input: lines, referenceTime_: referenceTime)
    case .passport:
        parse = reader.readTD3(input: lines, referenceTime_: referenceTime)
    case .idCard:
        parse = reader.readTD1(input: lines, referenceTime_: referenceTime)
    }
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
