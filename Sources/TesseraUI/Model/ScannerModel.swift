import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import Tessera
import UIKit

/// The scanner flow's state driver — the iOS mirror of the Android `ScannerFlow` composable's wiring. It
/// owns the `AVCaptureMrzScanner`, collects its per-frame `results` stream, applies the pure
/// ``reduceCameraResult(_:)`` → ``routeDecode(_:reviewMode:)`` decisions to ``state``, and exposes the
/// scanner's published `AVCaptureSession` for ``CameraPreviewView``. The root view (``RootScannerView``)
/// dispatches on ``state``; the model holds the one-shot decode latch, the camera-in-use self-resume, the
/// struggle timeout, the session-level scan deadline, and the method / rescan / manual-read hooks.
///
/// Everything is on the main actor: SwiftUI observation and the `AVCaptureMrzScanner` results are marshalled
/// here, matching how the Android flow runs on the composition thread. Reports back exactly once through
/// ``onResult`` — either a confirmed decode the user accepted or a cancellation.
@MainActor
@Observable
final class ScannerModel {
    /// The screen the UI is currently showing; the root view dispatches on this.
    private(set) var state: ScannerState

    /// The running `AVCaptureSession` to preview, or `nil` while headless / warming up. Observed by
    /// ``CameraPreviewView``; the initializing state shows while it is `nil`.
    private(set) var previewSession: AVCaptureSession?

    /// Drives the SwiftUI photo picker (``RootScannerView`` attaches `.photosPicker` to these). Saved-image
    /// reading is opt-in; the picker only ever appears when the consumer enabled ``ScanMethod/savedImage``.
    var photoPickerPresented = false
    var pickedItem: PhotosPickerItem?

    /// Whether the host has been handed a camera-permission request in this flow — the iOS analogue of the
    /// Android `hasAsked`. On iOS a status of anything other than `.notDetermined` also means the user has
    /// been asked, so the permanent-denial face is reached without a separate rationale signal.
    private var hasAskedPermission = false

    /// The trigger for the accepted-read confirm haptic (TES-134): bumped exactly when the live-camera
    /// consensus gate confirms a read, observed by the root view's `.sensoryFeedback` (which gates on
    /// ``MrzScannerConfig/hapticFeedback``). A counter — not a Bool — so back-to-back sessions retrigger.
    private(set) var confirmedReadHaptic = 0

    /// Whether the torch is currently on (reflected by the torch button). K/N does not expose the AVFoundation
    /// torch API, so the torch is driven here in Swift via the capture device published on the session.
    private(set) var torchOn = false
    // Applies `torchOnByDefault` once per session, so it is not re-forced on every preview-session update.
    private var torchDefaultApplied = false

    /// Whether the currently bound camera device has a flash/torch unit at all — the gate the torch button's
    /// visibility checks (TES-84 mirror of the Android `scanner.hasTorch()`). `AVCaptureMrzScanner` (the K/N
    /// scanner) exposes no `hasTorch`/`torch` seam of its own, so this is derived here from the published
    /// ``previewSession``'s bound video device — the same seam ``setTorch(_:)`` already reads. `false` while
    /// no session is live (nothing to check yet).
    var hasTorch: Bool {
        currentCaptureDevice()?.hasTorch ?? false
    }

    private let config: MrzScannerConfig
    private let onResult: (TesseraUIResult) -> Void

    /// The live scanner, created lazily when the camera path first runs (so a camera-disabled config never
    /// touches AVFoundation). `enablePreview()` is armed at construction, before `start()`.
    private var scanner: AVCaptureMrzScanner?

    /// The live scanner's Vision recognizer, kept so the viewfinder's measured guide region can retarget the
    /// OCR band after construction (``updateMrzGuideRegion(metadataRect:)``). Lives and dies with `scanner`.
    private var recognizer: VisionMrzTextRecognizer?
    private var resultsTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var struggleTask: Task<Void, Never>?

    /// A one-shot latch: once a decode has routed on (to review / read-failed / straight back), later decoded
    /// frames from the still-running stream must not re-fire. Kept as model state (not inside the collector)
    /// so it survives the state transitions the collector drives — e.g. a camera-in-use → scanning resume.
    private var decodeRouted = false

    /// Frame-agreement gate over the live decode stream (TES-91 mirror): a decode routes on only once
    /// ``consensusReads`` frames read the SAME document, so a transient OCR misread the MRZ has no check
    /// digit for (e.g. a filler `<` read as a letter in the name field) cannot win on one bad frame. Reset
    /// alongside ``decodeRouted`` whenever a fresh live session begins (``selectMethod(_:)``,
    /// ``rescan()``). Saved-image / manual entry are one-shot and route without this gate. Mirrors the
    /// Android `consensus` (`remember(config.consensusReads) { MrzDecodeConsensus(...) }`).
    private var consensus = MrzDecodeConsensus(threshold: ScannerModel.consensusReads)

    /// How many agreeing frames the live consensus gate requires before a reading is confirmed. Hardcoded to
    /// mirror `MrzDecodeConsensus.DEFAULT_THRESHOLD` (mrz-camera-core) — unlike the Android `MrzScannerConfig`,
    /// this iOS `MrzScannerConfig` has no `consensusReads` extension point yet, so there is nothing to plumb a
    /// consumer override through; add one here if/when the config gains that knob.
    private static let consensusReads: Int32 = 2

    /// Wall-clock of the last frame the consensus gate reported as gathering, so the "hold steady" cue lingers
    /// briefly instead of strobing: detection flickers frame-to-frame even on a steady card (a miss between
    /// two decodes is normal), so the cue clears only after ``gatheringCueLinger`` with no decode. Mirrors the
    /// Android `lastDecodeAtMs` / `GATHERING_CUE_LINGER_MS`.
    private var lastGatheringAt: Date?
    private let gatheringCueLinger: TimeInterval = 0.6

    /// TES-97 mirror: whether OCR has returned text for at least one frame during this scanning session — the
    /// gate for entering `struggling` (something is in view but unparseable) rather than staying on the plain
    /// framing guide (nothing has been in view at all, so "try more light or move farther away" would be
    /// misleading). Reset alongside ``decodeRouted`` whenever a fresh live session begins.
    private var sawTextEver = false

    /// TES-97 mirror: whether the configured struggle timeout has already elapsed for this session. Split
    /// from ``sawTextEver`` so a frame that only starts carrying text AFTER the timer already fired still
    /// flips the UI to struggling the moment it arrives (see the `.stayScanning` branch in
    /// ``onCameraResult(_:)``), rather than requiring text to have appeared before the timer.
    private var struggleTimeoutElapsed = false

    /// Guards ``armStruggleTimeout()`` so it fires once per live session, the first time the preview session
    /// goes live (mirrors the Android `awaitCameraActiveThenTimeout` gate) rather than at scan-intent —
    /// camera-boot time must not count against the struggle budget.
    private var struggleTimeoutArmed = false

    /// TES-93 mirror: the in-progress manual-entry text, hoisted here (survives the flow's lifetime) rather
    /// than living only inside `ScannerState.manualRaw` — which a naive `selectMethod` / `rescan` would
    /// rebuild from scratch (an empty `.manualRaw`), silently discarding whatever the user had typed on a
    /// Manual→other→Manual round trip.
    private var manualDraft = ""

    /// TES-137 mirror of the Android `MANUAL_ENTRY_MAX_CHARS`: a hard ceiling on the manual-entry draft's
    /// length, in characters. A real MRZ is at most 3 lines of 44 characters (132 chars) plus a little
    /// whitespace — 1024 is generously above that so a legitimate typed or pasted MRZ is never truncated,
    /// while an arbitrarily large paste is bounded before it reaches ``manualDraft`` / ``ScannerState``.
    /// Truncated, never rejected (reader, not oracle): a 1024-character draft is already not a readable MRZ
    /// regardless of where the excess came from.
    private static let manualEntryMaxChars = 1024

    // MARK: - Session scan deadline (TES-124/125/126)

    /// The time left for the countdown chip, or `nil` when `config.scanTimeout` is `nil` (no deadline → no
    /// chip). Refreshed on each ~500ms tick while the app is foreground. Mirrors the Android
    /// `rememberScanDeadline`'s returned `Duration?`.
    private(set) var timeRemaining: Duration?

    /// The pure accumulator behind the deadline (see ``DeadlineClock``); `nil` when `config.scanTimeout` is
    /// `nil` — the deadline never arms.
    private var deadlineClock: DeadlineClock?

    /// The monotonic clock the deadline measures active elapsed time against — never wall-clock `Date` (a
    /// clock change, DST, or NTP correction must never perturb the deadline). Mirrors the Android
    /// `SystemClock.elapsedRealtime()`.
    private let deadlineTickClock = ContinuousClock()

    /// The instant of the deadline's last tick while foreground, so each tick advances by the REAL elapsed
    /// time since then (drift-corrected), not the nominal 500ms interval. Mirrors the Android `lastTick`.
    private var deadlineLastTick: ContinuousClock.Instant?

    private var deadlineTask: Task<Void, Never>?

    /// Whether the app is currently foreground — the deadline advances only while this is `true`. Defaults to
    /// `true` (the scanner only ever appears while the app is already active); ``setForeground(_:)`` keeps it
    /// current as the scene phase changes.
    private var deadlineForeground = true

    init(config: MrzScannerConfig, onResult: @escaping (TesseraUIResult) -> Void) {
        self.config = config
        self.onResult = onResult
        self.state = initialState(enabledMethods: config.enabledMethods)
    }

    // MARK: - Lifecycle

    /// Starts the flow for the current initial state. Idempotent per entered method. Called by the root view
    /// on appear.
    func onAppear() {
        applyStateEntry(state)
        beginSession()
    }

    /// Tears the flow down — stops and closes the scanner and cancels the collectors, including the
    /// session-level deadline tick loop. Called on disappear.
    func onDisappear() {
        teardownScanner()
        deadlineTask?.cancel()
        deadlineTask = nil
    }


    // DECIDED (TES-129, 2026-07-30): flow state is deliberately NOT persisted across scene/process death —
    // no SceneStorage/Codable snapshot, unlike Android's saved-instance restoration (TES-102). iOS has no
    // config-change recreation (rotation loses nothing; this @Observable model is the in-memory layer that
    // survives view churn), so the only loss trigger is backgrounding plus memory eviction inside a
    // seconds-long flow — a re-scan costs seconds, and not persisting means the SDK never writes document
    // data of its own. Revisit only on real field reports of lost long manual entries, privacy-first.

    /// Starts the session-level scan-timeout deadline (TES-124) exactly once, independent of which screen or
    /// reading method is showing — called from ``onAppear()``, so it starts the moment the scanner UI appears
    /// and survives every later method switch, review, or manual-entry detour. A `nil` `config.scanTimeout`
    /// never arms (``timeRemaining`` stays `nil`, so the countdown chip never shows — Swift's `Duration` has
    /// no infinity sentinel, so `nil` plays the role the Android `Duration.INFINITE` does). Idempotent: a
    /// second call (e.g. a re-fired `.onAppear`) is a no-op once a deadline is already running.
    private func beginSession() {
        guard deadlineClock == nil, let timeout = config.scanTimeout else { return }
        deadlineClock = DeadlineClock(total: timeout)
        timeRemaining = timeout
        armDeadlineTickIfNeeded()
    }

    /// Forwards a scene-phase change from the root view's `@Environment(\.scenePhase)`. The deadline advances
    /// only while foreground — the iOS mirror of the Android session deadline's `Lifecycle.State.RESUMED`
    /// gate (`repeatOnLifecycle`): time spent backgrounded or on the lock screen does not count, and the
    /// deadline resumes from the accumulated elapsed time rather than restarting (TES-126). Camera-interrupted
    /// ("in use") time still counts — that is a foreground state; only backgrounding pauses the clock, since
    /// the pause is lifecycle-driven only, exactly like Android, never camera-driven.
    func setForeground(_ foreground: Bool) {
        guard deadlineForeground != foreground else { return }
        deadlineForeground = foreground
        guard deadlineClock != nil else { return }
        if foreground {
            armDeadlineTickIfNeeded()
        } else {
            deadlineTask?.cancel()
            deadlineTask = nil
        }
    }

    /// Arms the ~500ms deadline tick loop if a deadline is running, the app is foreground, and no loop is
    /// already active. Re-reads the tick clock's `now` as the new `deadlineLastTick` so the paused gap (while
    /// backgrounded) is never counted as elapsed active time.
    private func armDeadlineTickIfNeeded() {
        guard deadlineClock != nil, deadlineForeground, deadlineTask == nil else { return }
        deadlineLastTick = deadlineTickClock.now
        deadlineTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                // Exits the loop for good once the model itself is gone, rather than spinning forever on a
                // weak reference that will never resolve again.
                guard let self else { return }
                await MainActor.run { self.tickDeadline() }
            }
        }
    }

    /// One deadline tick: advances the accumulator by the REAL elapsed time since the last tick
    /// (drift-corrected by the monotonic clock, mirroring the Android tick's `now - lastTick`), refreshes
    /// ``timeRemaining`` for the countdown chip, and — the first time the accumulator reaches the total —
    /// ends the flow as `Cancelled(timedOut)` on whatever screen the user is currently on, exactly like the
    /// Android `onElapsed`.
    private func tickDeadline() {
        guard var clock = deadlineClock, let lastTick = deadlineLastTick else { return }
        let now = deadlineTickClock.now
        deadlineLastTick = now
        let justFired = clock.advance(by: lastTick.duration(to: now))
        deadlineClock = clock
        timeRemaining = clock.remaining
        if justFired {
            deadlineTask?.cancel()
            deadlineTask = nil
            onResult(.cancelled(.timedOut))
        }
    }

    // MARK: - VoiceOver announce-on-arrival (TES-58)

    /// Posts a VoiceOver announcement for `state`'s arrival, if it carries one (``announcementKey(for:)`` in
    /// ScannerDecisions.swift) — the iOS mirror of the Android live regions (`liveRegion =
    /// Assertive`/`Polite`). `UIAccessibility.announcement` has no polite/assertive tier, so both groups are
    /// posted identically here, immediately on arrival.
    private func postAnnouncement(for state: ScannerState) {
        guard let key = announcementKey(for: state) else { return }
        postAnnouncement(key: key)
    }

    /// Posts a plain-text VoiceOver announcement for a localization `key` directly — used for the
    /// struggling/gathering overlays, a rising-edge flag on `.scanning` rather than a distinct
    /// ``ScannerState`` case, so they can't go through ``postAnnouncement(for:)``'s state-keyed mapping. Every
    /// call site guards this to fire once, on the transition into the overlay — never on every recompute of
    /// an already-showing one, mirroring the Android `StrugglingHint`/`GatheringHint` polite live regions.
    private func postAnnouncement(key: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: String.LocalizationValue(key), bundle: .module)
        )
    }

    // MARK: - Global chrome hooks

    /// The global cancel (the top bar's ✕). Reports WHY the flow ended based on what the user was looking
    /// at when they closed (TES-115, the Android `dismissReasonFor` mirror): the terminal
    /// camera-unavailable screen → ``DismissReason/cameraUnavailable``, either permission screen →
    /// ``DismissReason/permissionDenied``, anything else — including the recoverable in-use notice —
    /// ``DismissReason/userDismissed``. The decision is the pure ``dismissReason(for:)``.
    func cancel() {
        onResult(.cancelled(dismissReason(for: state)))
    }

    /// Whether the manual-entry escape (offered from the struggling hint, both camera-status notices, and the
    /// permission gate) should be shown at all — `false` when the consumer's `enabledMethods` excludes
    /// `.manualEntry`, so a camera-only config never routes the user into a screen they cannot reach any other
    /// way. Mirrors the Android `showManualEntry`.
    var showManualEntry: Bool {
        config.enabledMethods.contains(.manualEntry)
    }

    /// Switching reading method from the switcher: camera → scanning, photo → the await-pick launcher state,
    /// type → manual raw (prefilled from the hoisted ``manualDraft``, TES-93 — a Manual→other→Manual round
    /// trip must not silently discard what the user already typed). Re-arms the decode latch and the live
    /// consensus / struggle-gate state so a fresh method starts clean. Mirrors the Android `onSelectMethod`.
    func selectMethod(_ method: ScanMethod) {
        resetLiveSessionGates()
        switch method {
        case .camera:
            transition(to: .scanning(struggling: false, gathering: false))
        case .savedImage:
            transition(to: .awaitingSavedImagePick)
        case .manualEntry:
            transition(to: .manualRaw(text: manualDraft, parseFailed: false))
        }
    }

    // MARK: - Per-screen hooks

    /// Rescanning / trying again: returns to whichever method produced the current outcome screen — the iOS
    /// mirror of the Android `returnToSource` (from a review, TES-92/TES-96) and the read-failed
    /// `ReadFailedContent.onTryAgain` (hardcoded to re-open the photo picker, since read-failed is only ever
    /// reached via saved-image — a live-camera parse failure never routes while the consensus gate is waiting
    /// for a clean frame, and manual entry now stays inline on a parse failure, see ``readManual(text:)``).
    /// Re-arms the decode latch and the live consensus / struggle-gate state so a fresh camera session starts
    /// clean.
    func rescan() {
        resetLiveSessionGates()
        switch state {
        case let .review(decoded, _, source):
            returnToSource(source, decoded: decoded)
        case .readFailed:
            launchPhotoPicker()
        default:
            transition(to: .scanning(struggling: false, gathering: false))
        }
    }

    /// Returns to whichever reading method produced a ``ScannerState/review(decoded:expanded:source:)`` —
    /// camera → the live preview, saved-image → re-open the picker, manual → the entry screen, PREFILLED with
    /// the lines that were actually submitted for this review (TES-93 — editing a manual-provenance reading
    /// should not start from a blank field). Mirrors the Android `returnToSource`.
    private func returnToSource(_ source: ScanMethod, decoded: MrzScanResultDecoded) {
        switch source {
        case .camera:
            transition(to: .scanning(struggling: false, gathering: false))
        case .savedImage:
            launchPhotoPicker()
        case .manualEntry:
            manualDraft = decoded.recognizedText.lines.map(\.text).joined(separator: "\n")
            transition(to: .manualRaw(text: manualDraft, parseFailed: false))
        }
    }

    /// Clears the one-shot decode latch and the live-session gates (consensus tally, struggle-gate latches,
    /// the struggle-timer arm latch) — called whenever a fresh live session begins (``selectMethod(_:)``,
    /// ``rescan()``), mirroring the Android flow's paired resets of `decodeRouted` / `consensus` /
    /// `sawTextEver` / `struggleTimeoutElapsed`.
    private func resetLiveSessionGates() {
        decodeRouted = false
        consensus.reset()
        sawTextEver = false
        struggleTimeoutElapsed = false
        struggleTimeoutArmed = false
    }

    /// Enter manual raw entry (the read-failed / struggle escape), prefilled from the hoisted ``manualDraft``.
    func enterManualEntry() {
        transition(to: .manualRaw(text: manualDraft, parseFailed: false))
    }

    /// Bind the in-progress manual text (called on every edit) — mirrored into the hoisted ``manualDraft``
    /// (TES-93) and clears a prior parse-failed note (the input the user is fixing is no longer "failed").
    /// TES-137: truncated to ``manualEntryMaxChars`` before it reaches ``manualDraft`` / ``ScannerState`` —
    /// bounds a large paste at the source, mirroring the Android `MANUAL_ENTRY_MAX_CHARS` cap.
    func updateManualText(_ text: String) {
        let bounded = String(text.prefix(Self.manualEntryMaxChars))
        manualDraft = bounded
        state = .manualRaw(text: bounded, parseFailed: false)
    }

    /// Assemble a `Decoded` from the typed text (pure, host-tested; format auto-detected). A success /
    /// partial-success routes to review (or straight back under instant-return) exactly as a camera decode
    /// does. A parse failure stays HERE with an inline note — the typed text is preserved and there is no jump
    /// to the camera/photo-flavoured read-failed screen. Mirrors the Android manual-entry `onRead`.
    func readManual(text: String) {
        let decoded = assembleManualDecoded(text: text)
        if decoded.parse is ParseResult.Failure {
            state = .manualRaw(text: text, parseFailed: true)
        } else {
            routeThroughDecode(decoded, source: .manualEntry)
        }
    }

    // MARK: - Saved-image reading

    /// Present the system photo picker (the "Choose photo" affordances route here).
    func launchPhotoPicker() {
        photoPickerPresented = true
    }

    /// A photo was picked: show the analyzing state and read it on-device. Mirrors the Android
    /// `readPickedImage`.
    func handlePickedItem(_ item: PhotosPickerItem) {
        pickedItem = nil
        state = .savedImageAnalyzing
        postAnnouncement(for: .savedImageAnalyzing)
        Task { await readPickedPhoto(item) }
    }

    /// Reads the picked photo through the `SavedImageMrzReader` in single-read mode, entirely on-device, then
    /// applies the pure ``mapSavedImageResult(_:)``: a single decode → routed exactly as a camera decode;
    /// nothing readable → the empty screen. Single read, like the live camera (TES-86/TES-91) — no tolerant
    /// candidate enumeration and no "choose the reading" screen; if OCR misread an ambiguous glyph, the
    /// review's check-digit observations surface it and the user rescans, the same safety net the camera has.
    /// Saved-image reading is opt-in and off by default — reaching here means the consumer enabled
    /// ``ScanMethod/savedImage``, which IS the acknowledgement (ADR-023), so the acknowledgement is
    /// constructed here with no separate screen.
    private func readPickedPhoto(_ item: PhotosPickerItem) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let url = writeTempImage(data)
        else {
            state = .savedImageEmpty
            postAnnouncement(for: .savedImageEmpty)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let acknowledgement = SavedImageReadingAcknowledgement()
        // F = NSURL: the iOS Vision saved-image recognizer reads from a file URL (it applies the file's EXIF
        // orientation). The factory returns a type-erased recognizer, so the reader's frame type is pinned here.
        let reader = SavedImageMrzReader<NSURL>(
            acknowledgement: acknowledgement,
            recognizer: VisionSavedImageRecognizerKt.visionSavedImageRecognizer(acknowledgement: acknowledgement),
            // LENIENT, mirroring the Android saved-image path and this file's own live-camera reasoning
            // (TES-86/TES-129): Vision routinely injects stray spaces into MRZ lines — in photos exactly as
            // in camera frames — and under STRICT those lines fail their fixed width, so a perfectly
            // readable photo reports "no MRZ" (device-verified 2026-08-09). Whitespace is never meaningful
            // in an MRZ, so stripping it is safe.
            mode: ParsingMode.lenient,
            // Single read, like the live camera — no tolerant candidate enumeration and no "Choose the
            // reading" screen (TES-86/TES-91). A photo takes its one best read straight to review; if OCR
            // misread an ambiguous glyph, the review's check-digit observations surface it and the user
            // rescans. (Headless consumers can still opt into tolerant reading via `SavedImageMrzReader`
            // directly.)
            tolerant: false,
            metadataReader: nil,
            metadataPolicy: CaptureMetadataPolicy.none,
            telemetry: NoOpTelemetrySink(),
            // @Sendable so the closure does NOT inherit this model's main-actor isolation: the K/N analyzer
            // invokes it on its background analysis thread — and only on a SUCCESSFUL decode (it timestamps
            // the decode), which is why the isolation trap stayed latent until the first photo actually
            // decoded (SIGTRAP via dispatch_assert_queue, device crash log 2026-08-09). `nowInstant()` is a
            // free function touching no actor state, so the hop is safe.
            referenceTimeProvider: { @Sendable in nowInstant() }
        )
        // The scan result is a non-Sendable K/N type produced on Vision's callback thread; move it onto the
        // main actor as a single-owner transfer (the same discipline the flow-collection bridge uses).
        let boxed: UnsafeTransfer<SavedImageScanResult?> = await withCheckedContinuation { continuation in
            reader.read(image: url as NSURL) { scanResult, _ in
                continuation.resume(returning: UnsafeTransfer(scanResult))
            }
        }
        let result = boxed.value
        reader.close()

        // Arm the decode latch afresh so a single-decode route fires.
        decodeRouted = false
        guard let result else {
            state = .savedImageEmpty
            postAnnouncement(for: .savedImageEmpty)
            return
        }
        switch mapSavedImageResult(result) {
        case let .singleDecode(decoded):
            routeThroughDecode(decoded, source: .savedImage)
        case .empty:
            state = .savedImageEmpty
            postAnnouncement(for: .savedImageEmpty)
        }
    }

    private func writeTempImage(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-picked-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Toggle the review screen's expanded all-fields view.
    func toggleReviewExpanded() {
        guard case let .review(decoded, expanded, source) = state else { return }
        state = .review(decoded: decoded, expanded: !expanded, source: source)
    }

    /// Confirm the reviewed decode — hand it back to the host.
    func confirmReview() {
        guard case let .review(decoded, _, _) = state else { return }
        onResult(.confirmed(decoded))
    }

    // MARK: - State transitions

    /// Moves to a new state and runs its entry side effects (start/stop scanner, launch picker, arm the
    /// struggle timer). Centralised so every transition — switcher, rescan, decode routing — goes through the
    /// same entry wiring, mirroring how the Android flow reacts to `uiState` changes.
    private func transition(to newState: ScannerState) {
        state = newState
        postAnnouncement(for: newState)
        applyStateEntry(newState)
    }

    private func applyStateEntry(_ newState: ScannerState) {
        switch newState {
        case .scanning:
            // The camera-permission gate (the iOS mirror of Android's CameraCapture gate). The SDK only READS
            // the authorization status — it never calls requestAccess itself (scope permission boundary); the
            // host asks via config.onRequestPermission. A non-granted status diverts to the permission face.
            switch evaluatePermission() {
            case .granted:
                startScanningIfNeeded()
            case .needsGrant:
                teardownScanner()
                state = .permissionNeeded
            case .permanentlyDenied:
                teardownScanner()
                state = .permissionPermanentlyDenied
            }
        case .awaitingSavedImagePick:
            // Entering the saved-image entry point launches the picker. If the user dismisses it with no
            // photo, the AwaitingSavedImagePickScreen shows a neutral re-pick prompt (never blank).
            teardownScanner()
            launchPhotoPicker()
        default:
            // Outcome / gate / manual screens do not run the camera.
            teardownScanner()
        }
    }

    // MARK: - Permission gate

    /// The permission face to show, computed from the read-only AVFoundation authorization status via the
    /// shared pure ``permissionScreenState(granted:hasAsked:showRationale:)``. iOS has no rationale signal, so
    /// `showRationale` is always `false`; a determined status (`.denied`/`.restricted`) maps to `hasAsked` so
    /// the pure function yields the permanently-denied face, and `.notDetermined` yields needs-grant.
    private func evaluatePermission() -> PermissionScreenState {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return permissionScreenState(
            granted: status == .authorized,
            hasAsked: hasAskedPermission || status != .notDetermined,
            showRationale: false
        )
    }

    /// The permission screen's primary "Grant access" action: hand the request to the host (the SDK never
    /// requests a permission itself). Marks that we've asked so a later denial reaches the permanent-denial
    /// face on the next foreground re-check. No-op-safe when the host supplied no handler (the screen hides
    /// the button in that case).
    func requestPermission() {
        hasAskedPermission = true
        config.onRequestPermission?()
    }

    /// Opens this app's Settings page so the user can turn Camera on after a denial — UI navigation, not a
    /// permission request (within the permission boundary).
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Re-evaluate the permission when the app returns to the foreground, so a grant made via the host's
    /// request OR via the Settings screen takes effect without relaunching. Only acts while a permission face
    /// is showing: a fresh grant resumes scanning.
    func recheckPermissionOnForeground() {
        switch state {
        case .permissionNeeded, .permissionPermanentlyDenied:
            switch evaluatePermission() {
            case .granted:
                transition(to: .scanning(struggling: false, gathering: false))
            case .needsGrant:
                state = .permissionNeeded
            case .permanentlyDenied:
                state = .permissionPermanentlyDenied
            }
        default:
            break
        }
    }

    // MARK: - Camera wiring

    /// Starts (or keeps running) the live scanner for the scanning state. Constructs the scanner with preview
    /// armed on first use and begins collecting `results` and `previewSession`. The struggle timeout is armed
    /// separately, once the preview actually goes live (see ``deliverPreviewSession(_:)`` — TES-97 item 6),
    /// not here at scan-intent. The session-level scan deadline is NOT armed here either — unlike the old
    /// camera-scoped timer this replaced, it lives at the whole-flow level (``beginSession()``, called once
    /// from ``onAppear()``) and runs independently of whether the camera is even the active method.
    private func startScanningIfNeeded() {
        if scanner != nil { return }
        struggleTimeoutArmed = false

        // The permission gate lives in applyStateEntry (permissionScreenState over the read-only
        // authorization signals), which routes to a permission state BEFORE this is reached from .scanning;
        // the scanner's own CaptureError(PermissionDenied) stays non-terminal in reduceCameraResult.
        // Restrict OCR to the MRZ band the guide marks (TES-86 mirror): Vision reads only the guide-box
        // band, not the whole frame — noise above the MRZ (name, address lines) otherwise breaks detection.
        // Opt-in, so headless consumers' default reading is unchanged. The parameterless call is the centred
        // approximation until the viewfinder reports the guide's real on-screen region (aspect-fill crops
        // the frame and the guide sits low, so the two genuinely differ); the WYSIWYG rect then retargets it
        // via updateMrzGuideRegion — the iOS mirror of Android's ViewPort alignment.
        let recognizer = VisionMrzTextRecognizer()
        recognizer.restrictToMrzBand()
        self.recognizer = recognizer
        let scanner = AVCaptureMrzScanner(
            recognizer: recognizer,
            // LENIENT strips whitespace before shape-matching, exactly as the Android live camera does
            // (TES-86): Vision routinely injects spaces into MRZ lines, and under STRICT those lines fail
            // their fixed width so the MRZ band is never detected. Whitespace is never meaningful in an MRZ,
            // so stripping it is safe.
            mode: ParsingMode.lenient,
            telemetry: NoOpTelemetrySink(),
            cameraPosition: 1 // AVCaptureDevicePositionBack
        )
        scanner.enablePreview()
        self.scanner = scanner

        // Collect every per-frame result and forward it to the pure reducer, and observe the published
        // AVCaptureSession for the preview. The one-shot decode latch lives here in the model (not the
        // collector), so the collector stays a plain forwarder and the camera keeps running under a notice so
        // a recoverable in-use interruption can self-resume. The K/N flow types are not Sendable, so the
        // collect loops run in `nonisolated` helpers that own the flow off-actor and hop each value back to
        // the main actor — the only actor that touches model state (mirrors the harness's collect bridge).
        // The K/N flow types are not Sendable; they are thread-confined and, here, only ever touched from the
        // collect loop. Each flow is boxed in an `@unchecked Sendable` wrapper so it can be handed to a Task,
        // and each collector forwards every value to the main actor (the only actor that touches model state)
        // via a `Task { @MainActor }` hop. Mirrors the harness's ResultCollector bridge.
        let resultsBox = FlowBox(scanner.results)
        let previewBox = FlowBox(scanner.previewSession)
        resultsTask = Task {
            let collector = FlowCollector { [weak self] value in
                guard let result = value as? MrzScanResult else { return }
                await self?.deliverCameraResult(UnsafeTransfer(result))
            }
            try? await resultsBox.flow.collect(collector: collector)
        }
        previewTask = Task {
            let collector = FlowCollector { [weak self] value in
                await self?.deliverPreviewSession(UnsafeTransfer(value as? AVCaptureSession))
            }
            try? await previewBox.flow.collect(collector: collector)
        }

        scanner.start()
    }

    /// After the configured struggle timeout with no decode, marks the timeout elapsed and — if OCR has
    /// already seen text at least once this session (``sawTextEver``) — flips the scanning state to
    /// `struggling`. The camera keeps running, so a decode arriving later still routes; a non-finite timeout
    /// means "never struggle", so the timer does not arm. A later qualifying frame after the timer still flips
    /// it on retroactively (see the `.stayScanning` branch in ``onCameraResult(_:)``). Armed once per live
    /// session the first time the preview goes live (``deliverPreviewSession(_:)``, TES-97 item 6) — not at
    /// scan-intent — so camera-boot time is never counted against the budget. Mirrors the Android struggle
    /// `LaunchedEffect` / `onStruggling`.
    private func armStruggleTimeout() {
        struggleTask?.cancel()
        // A nil struggleTimeout means "never struggle".
        guard let timeout = config.struggleTimeout else { return }
        let nanos = nanoseconds(for: timeout)
        struggleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.struggleTimeoutElapsed = true
                guard case let .scanning(struggling, gathering) = self.state, !struggling, self.sawTextEver else { return }
                self.state = .scanning(struggling: true, gathering: gathering)
                self.postAnnouncement(key: "tessera_scanner_struggling_hint")
            }
        }
    }

    /// Nanoseconds for `Task.sleep`, clamped at ≥0. Used by the struggle timer's `Task.sleep(nanoseconds:)`
    /// call (the session deadline below uses `Task.sleep(for:)` directly on a fixed 500ms tick instead).
    private func nanoseconds(for duration: Duration) -> UInt64 {
        UInt64(max(0, duration.components.seconds)) * 1_000_000_000
            + UInt64(max(0, duration.components.attoseconds / 1_000_000_000))
    }

    private func teardownScanner() {
        // The torch turns off when the session stops; reset the flags so a re-start reapplies torchOnByDefault.
        torchOn = false
        torchDefaultApplied = false
        struggleTask?.cancel(); struggleTask = nil
        struggleTimeoutArmed = false
        lastGatheringAt = nil
        resultsTask?.cancel(); resultsTask = nil
        previewTask?.cancel(); previewTask = nil
        previewSession = nil
        scanner?.stop()
        scanner?.close()
        scanner = nil
        recognizer = nil
    }

    /// Retargets the OCR band to the guide's real on-screen region — called by the viewfinder whenever its
    /// layout resolves or changes, with the guide rect already converted by AVFoundation's own
    /// `metadataOutputRectOfInterest(for:)` (so `metadataRect` is normalized against the unrotated capture
    /// buffer, top-left origin — the recognizer maps it into Vision's space internally). No-op when the
    /// live scanner is not running (nothing to retarget; a later start re-reports on layout).
    func updateMrzGuideRegion(metadataRect: CGRect) {
        recognizer?.restrictToMrzBand(
            x: metadataRect.origin.x,
            y: metadataRect.origin.y,
            width: metadataRect.size.width,
            height: metadataRect.size.height
        )
        // Aim continuous AF at the same region (TES-132): the guide window is not the frame centre, and
        // centre-weighted AF otherwise focuses the background while the document blurs. Same converted
        // rect — focusPointOfInterest documents the same metadata-output space.
        scanner?.focusOnRegion(
            x: metadataRect.origin.x,
            y: metadataRect.origin.y,
            width: metadataRect.size.width,
            height: metadataRect.size.height
        )
    }

    /// Main-actor delivery of one collected result. The value is non-Sendable (a K/N reference type), so it
    /// crosses from the collect loop wrapped in an ``UnsafeTransfer`` — safe because the collector produces
    /// one value at a time and never touches it again after handing it over (a single-owner transfer).
    private func deliverCameraResult(_ result: UnsafeTransfer<MrzScanResult>) {
        onCameraResult(result.value)
    }

    /// Main-actor delivery of the latest published `AVCaptureSession` (or `nil`), for the preview view.
    private func deliverPreviewSession(_ session: UnsafeTransfer<AVCaptureSession?>) {
        previewSession = session.value
        guard session.value != nil else { return }
        // Honour torchOnByDefault the first time the camera opens (the device is now reachable via the session).
        if config.torchOnByDefault, !torchDefaultApplied {
            torchDefaultApplied = true
            setTorch(true)
        }
        // TES-97 item 6: the struggle timeout is camera-scoped and must measure time actively scanning, not
        // camera boot — arm it the first time the preview session goes live this session (mirrors the Android
        // `awaitCameraActiveThenTimeout` gate ahead of the struggle `LaunchedEffect`), not at scan-intent.
        if !struggleTimeoutArmed {
            struggleTimeoutArmed = true
            armStruggleTimeout()
        }
    }

    // MARK: - Torch

    /// Toggle the torch (the torch button's action).
    func toggleTorch() {
        setTorch(!torchOn)
    }

    /// Sets the active camera's torch on/off via the device published on the session. A no-op if the camera
    /// isn't open yet or has no torch. Kotlin/Native doesn't bind the AVFoundation torch category, so this
    /// lives in Swift; it's safe because torch is a device-level property orthogonal to the session config.
    private func setTorch(_ on: Bool) {
        guard let device = currentCaptureDevice(), device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            // Torch config can fail transiently (device busy); leave the state unchanged.
        }
    }

    /// The active video capture device, reached from the running session the scanner publishes.
    private func currentCaptureDevice() -> AVCaptureDevice? {
        previewSession?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }?
            .device
    }

    /// The continuous state reducer over the scanner's result stream — the iOS mirror of the Android
    /// `onCameraResult`. Every per-frame result runs through the pure ``reduceCameraResult(_:)`` and the
    /// resulting effect is applied here. Repeated decoded frames are guarded by the ``decodeRouted`` latch
    /// (route only the first). A camera-in-use notice self-resumes: any later non-error result flips the flow
    /// back to scanning, so no retry is needed.
    ///
    /// A decoded frame is a transient bad frame if it did not parse (blurred/garbled OCR) — live camera keeps
    /// scanning and waits for a clean frame rather than committing to read-failed on one bad read (TES-86); a
    /// parseable frame is offered to the consensus gate (``consensus``) rather than routed on sight, so a
    /// transient misread the MRZ has no check digit for cannot win on one frame — Gathering keeps scanning
    /// (surfacing the "hold steady" cue), Confirmed routes once (the latch stops repeats). Mirrors the Android
    /// `onCameraResult`'s consensus wiring (TES-91).
    private func onCameraResult(_ result: MrzScanResult) {
        switch reduceCameraResult(result) {
        case let .goDecoded(decoded):
            guard !decodeRouted, !(decoded.parse is ParseResult.Failure) else { return }
            switch consensus.offer(decoded: decoded) {
            case is ConsensusVerdictConfirmed:
                decodeRouted = true
                // TES-134 (Android hapticFeedback mirror): bump the sensory-feedback trigger the moment a
                // live-camera read is accepted — the view's `.sensoryFeedback` plays the confirm haptic
                // (gated there on `config.hapticFeedback`). Camera path only, exactly like Android.
                confirmedReadHaptic += 1
                routeThroughDecode(decoded, source: .camera)
            case is ConsensusVerdictGathering:
                lastGatheringAt = Date()
                if case let .scanning(struggling, gathering) = state, !gathering {
                    state = .scanning(struggling: struggling, gathering: true)
                    postAnnouncement(key: "tessera_scanner_gathering_hint")
                }
            default:
                break
            }
        case .goCameraInUse:
            state = .cameraInUse
            postAnnouncement(for: .cameraInUse)
        case .goCameraUnavailable:
            state = .cameraUnavailable
            postAnnouncement(for: .cameraUnavailable)
        case let .stayScanning(sawText):
            // TES-97: fold whether OCR has returned text at least once this session — the gate for whether the
            // struggle timeout is allowed to show struggling at all (see armStruggleTimeout()).
            sawTextEver = struggleGateAdvance(sawTextEver: sawTextEver, sawText: sawText)

            // A transient miss. If a recoverable camera-in-use notice is showing, a clean frame proves the
            // camera reconnected — return to scanning.
            if case .cameraInUse = state {
                state = .scanning(struggling: false, gathering: false)
                return
            }
            guard case let .scanning(struggling, gathering) = state else { return }
            var newStruggling = struggling
            var newGathering = gathering
            // Clear the "hold steady" cue only after the linger window with no decode, so a single miss
            // between two decodes (normal even on a steady card) does not strobe it.
            if newGathering, let lastGathering = lastGatheringAt,
               Date().timeIntervalSince(lastGathering) > gatheringCueLinger {
                newGathering = false
            }
            // TES-97: the struggle timeout already elapsed, but nothing carried text until just now — this
            // qualifying frame arriving late still flips the UI to struggling retroactively.
            if !newStruggling, struggleTimeoutElapsed, sawTextEver {
                newStruggling = true
            }
            if newStruggling != struggling || newGathering != gathering {
                state = .scanning(struggling: newStruggling, gathering: newGathering)
                // Announce only the rising edge (false → true), never the falling edge or an unrelated change.
                if newStruggling, !struggling {
                    postAnnouncement(key: "tessera_scanner_struggling_hint")
                }
            }
        }
    }

    /// Routes a decode to the matching state via ``routeDecode(_:reviewMode:)`` — shared by the camera path,
    /// manual entry, and saved-image, all of which produce a `Decoded` that follows the identical routing.
    /// `source` is carried onto ``ScannerState/review(decoded:expanded:source:)`` so a rescan/edit-entry
    /// returns to the method that produced it (TES-92/TES-93/TES-96). Mirrors the Android `routeDecoded` /
    /// `routeThroughDecode`.
    private func routeThroughDecode(_ decoded: MrzScanResultDecoded, source: ScanMethod) {
        switch routeDecode(decoded, reviewMode: config.reviewMode) {
        case let .showReadFailed(capturedText):
            transition(to: .readFailed(capturedText: capturedText))
        case let .returnConfirmed(decoded):
            onResult(.confirmed(decoded))
        case let .showReview(decoded):
            transition(to: .review(decoded: decoded, expanded: false, source: source))
        }
    }
}

// MARK: - Flow collection bridging

/// A single-owner transfer box for moving a non-Sendable value across an isolation boundary when the value is
/// produced, handed over, and never touched again by the sender (the K/N collect loop yields one value at a
/// time). `@unchecked Sendable` because that ownership discipline — not the type — makes the move safe.
private struct UnsafeTransfer<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Wraps a non-Sendable K/N flow so it can be handed to a `Task`. The flow is thread-confined and only ever
/// touched inside the collect loop, so the wrapper is `@unchecked Sendable`.
private struct FlowBox: @unchecked Sendable {
    let flow: any Kotlinx_coroutines_coreFlow
    init(_ flow: any Kotlinx_coroutines_coreFlow) { self.flow = flow }
}

/// Bridges a Kotlin `Flow` to an `async` Swift callback carrying each emitted value (`Any?`). Conforming to
/// the exported ObjC `FlowCollector` protocol requires an `NSObject` subclass; the suspend `emit` bridges to
/// Swift `async`. Same pattern as the device-verification harness's `ResultCollector`. `@unchecked Sendable`:
/// the callback is `@Sendable` and each raw value is delivered onward to the main actor as a single-owner
/// transfer.
private final class FlowCollector: NSObject, Kotlinx_coroutines_coreFlowCollector, @unchecked Sendable {
    private let onValue: @Sendable (Any?) async -> Void
    init(_ onValue: @escaping @Sendable (Any?) async -> Void) { self.onValue = onValue }
    func emit(value: Any?) async throws {
        await onValue(value)
    }
}
