import Tessera

/// The screen the default scanner UI is currently showing - the single state the flow (``ScannerModel``)
/// dispatches on. The iOS mirror of the Android `ScannerUiState` sealed model: every reading method and
/// every outcome the UI can be in is one case here, so the root view is one exhaustive `switch` over this
/// contract rather than a tangle of booleans. Nothing here is public - the frozen surface stays
/// ``MrzScannerView`` + ``MrzScannerConfig`` + ``TesseraUIResult`` (ADR-007); this is internal wiring.
///
/// The camera-initializing state (mockup 01b) is deliberately **not** a case here: it is not a flow state
/// the reducer can produce but a transient of the live preview - the window where the scanner has not yet
/// published an `AVCaptureSession`. It is therefore rendered by ``CameraPreviewView`` keyed on that nil
/// session, not dispatched by the model, so it stays where its real device-driven trigger lives.
enum ScannerState {
    /// The live camera preview is running and looking for an MRZ (mockup 01). `struggling` flips true once
    /// the configured struggle timeout elapses with no decode, to overlay the "still looking / type it
    /// instead" hint on the preview (mockup 02). `gathering` flips true while the frame-agreement consensus
    /// gate (``MrzDecodeConsensus``) has seen a parseable decode but has not yet reached agreement across
    /// enough frames, to overlay the "hold steady" cue - it takes render precedence over `struggling`, since
    /// getting a decode at all means progress is being made. Mirrors the Android `Scanning(struggling,
    /// gathering)`.
    ///
    /// `notAccepted` (TES-103) is the refusal (a category, or a kind that could not be told) of the last reading
    /// the frames agreed on that the app does not accept (``MrzScannerConfig/acceptedDocumentTypes``). While set, the preview shows a notice saying what kind was
    /// read and what kinds the app accepts; the camera keeps scanning. It renders below gathering and above
    /// struggling, and clears when an accepted reading starts gathering or 3 seconds after the last frame of
    /// that document. Mirrors the Android `Scanning.notAccepted`.
    case scanning(struggling: Bool, gathering: Bool, notAccepted: NotAcceptedKind? = nil)

    /// The camera permission is not held and can still be requested (mockup 04).
    case permissionNeeded

    /// The camera permission was denied with "don't ask again" - only the OS settings can grant it (mockup 04b).
    case permissionPermanentlyDenied

    /// Another app holds the camera, so this session cannot open it (mockup 05).
    case cameraInUse

    /// The camera could not be started for a non-recoverable reason (mockup 05b).
    case cameraUnavailable

    /// An MRZ decoded and the user is reviewing the parsed fields and observations before accepting (mockup
    /// 03 for a clean read, 03b for a check-digit mismatch). `expanded` toggles the all-fields + raw-MRZ view
    /// (mockup 03c). `decoded` is the SDK's verbatim result, carried as-is - the UI adds no judgement of its
    /// own (Principle 1). `source` is which method produced this reading, so a rescan/edit-entry returns to
    /// the method that produced it - camera, saved-image, or manual (prefilling the typed lines back, TES-93) -
    /// rather than always the live camera. Mirrors the Android `Review(decoded, expanded, source)`.
    case review(decoded: MrzScanResultDecoded, expanded: Bool, source: ScanMethod)

    /// OCR produced text that did not parse as any known MRZ format (a `ParseResultFailure`), so the captured
    /// text is shown verbatim for the user to retry or switch to manual entry (mockup 08). `capturedText` is
    /// the raw recognized text exposed as-is, garbles preserved (Principle 5).
    case readFailed(capturedText: RecognizedText)

    /// The saved-image method is the entry point and the flow is waiting for the photo picker to be launched.
    /// A momentary state: the model triggers the picker on entering it - either a pick routes on (analyzing →
    /// single decode / empty) or a dismissed picker leaves this showing a neutral re-pick prompt, so the
    /// screen is never blank.
    case awaitingSavedImagePick

    /// A picked photo is being analysed for an MRZ (mockup 07c).
    case savedImageAnalyzing

    /// The picked photo contained no readable MRZ (mockup 07b).
    ///
    /// - Note: there is deliberately no candidates state here - saved-image reading runs a single strict
    ///   decode (`tolerant: false`, mirroring the Android saved-image flow, TES-86/TES-91), so a picked photo
    ///   either decodes (routes exactly like a camera decode) or reads as empty; there is never a set of
    ///   candidate reconstructions to choose among (the old candidates screen was removed with its Android
    ///   counterpart).
    case savedImageEmpty

    /// A picked photo read as a document the app does not accept (`read`: a category outside
    /// ``MrzScannerConfig/acceptedDocumentTypes``, or a kind that could not be told, TES-341). The screen states what kind was read and what
    /// kinds the app accepts, and offers another photo. The reading itself is not kept. Mirrors the Android
    /// `SavedImageNotAccepted`.
    case savedImageNotAccepted(read: NotAcceptedKind)

    /// Manual entry of the MRZ lines as raw text (mockup 06). `text` is the in-progress input. `parseFailed`
    /// is set when the last submitted read did not parse - an inline note shown on this same screen, never a
    /// jump to the read-failed screen (which is camera/photo-flavoured and would mislabel typed input). Any
    /// edit clears it (see ``ScannerModel/updateManualText(_:)``). Mirrors the Android `ManualRaw(text,
    /// parseFailed)`.
    ///
    /// `notAccepted` (TES-103) is set when the typed lines read as a document the app does not accept
    /// (``MrzScannerConfig/acceptedDocumentTypes``; a kind that could not be told counts when the set is limited): the text stays and an inline note shows instead of
    /// review. Any edit clears it, like `parseFailed`.
    case manualRaw(text: String, parseFailed: Bool, notAccepted: NotAcceptedKind? = nil)
}
