import AVFoundation
import Combine
import SwiftUI
import Tessera
import UIKit

/// The scanner flow's state driver - the iOS mirror of the Android `ScannerFlow` composable's wiring. It
/// owns the `AVCaptureMrzScanner`, collects its per-frame `results` stream, applies the pure
/// ``reduceCameraResult(_:)`` → ``routeDecode(_:reviewMode:)`` decisions to ``state``, and exposes the
/// scanner's published `AVCaptureSession` for ``CameraPreviewView``. The root view (``RootScannerView``)
/// dispatches on ``state``; the model holds the one-shot decode latch, the camera-in-use self-resume, the
/// struggle timeout, the session-level scan deadline, and the method / rescan / manual-read hooks.
///
/// An `ObservableObject` (not `@Observable`, which needs iOS 17): the properties the root view reads are
/// `@Published`; everything else is plain, so per-frame bookkeeping (the linger timestamps, the consensus
/// tally) never republishes the screen. ``state`` is the only published property a camera frame can write,
/// and only when the screen changes (see ``updateState(_:)``).
///
/// Everything is on the main actor: SwiftUI observation and the `AVCaptureMrzScanner` results are marshalled
/// here, matching how the Android flow runs on the composition thread. Reports back exactly once through
/// ``onResult`` - either a confirmed decode the user accepted or a cancellation.
@MainActor
final class ScannerModel: ObservableObject {
    // COMPAT-NOTE(iOS 17): not a shim; this is the one implementation for every version. It could move back to
    // `@Observable` (with `@State` in ``RootScannerView``) when the minimum is iOS 17.

    /// The screen the UI is currently showing; the root view dispatches on this.
    @Published private(set) var state: ScannerState

    /// The running `AVCaptureSession` to preview, or `nil` while headless / warming up. Observed by
    /// ``CameraPreviewView``; the initializing state shows while it is `nil`.
    @Published private(set) var previewSession: AVCaptureSession?

    /// Drives the photo picker (``RootScannerView`` presents it: `.photosPicker` on iOS 16+, a
    /// `PHPickerViewController` below). Saved-image reading is opt-in; the picker only ever appears when the
    /// consumer enabled ``ScanMethod/savedImage``. The picked photo comes back through
    /// ``handlePickedImage(load:)``, so the model holds no picker-specific type.
    @Published var photoPickerPresented = false

    // No "has asked" flag (the Android `hasAsked`): on iOS the status itself says whether the person has
    // answered. A tap on Continue is not an answer - the status stays `.notDetermined` while the system dialog
    // is up and can still read so for a moment after the app becomes active again - so treating the tap as
    // "asked" showed the Settings face for a request that was about to be granted (TES-343).

    /// The camera authorization status, read and never requested. A seam so a host test can play a grant or a
    /// denial; the screen always reads AVFoundation.
    var authorizationStatus: () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) }

    /// How often, in nanoseconds, the permission screen re-reads an undecided status (see
    /// ``watchPermissionWhileUndecided()``). A seam so a host test need not wait.
    var permissionPollInterval: UInt64 = 250_000_000

    /// Watches an undecided camera permission while a permission screen shows; `nil` otherwise. Readable
    /// inside the module so a host test can say whether the watcher runs.
    private(set) var permissionWatchTask: Task<Void, Never>?

    /// Test-only: when set, called instead of building and starting the real camera, so a host test can see
    /// that the camera would start without AVFoundation.
    var cameraStartOverride: (() -> Void)?

    /// The trigger for the accepted-read confirm haptic (TES-134): bumped exactly when the live-camera
    /// consensus gate confirms a read, observed by the root view's `.sensoryFeedback` (which gates on
    /// ``MrzScannerConfig/hapticFeedback``). A counter - not a Bool - so back-to-back sessions retrigger.
    @Published private(set) var confirmedReadHaptic = 0

    /// Whether the torch is currently on (reflected by the torch button). K/N does not expose the AVFoundation
    /// torch API, so the torch is driven here in Swift via the capture device published on the session.
    @Published private(set) var torchOn = false
    // Applies `torchOnByDefault` once per session, so it is not re-forced on every preview-session update.
    private var torchDefaultApplied = false

    /// Whether the currently bound camera device has a flash/torch unit at all - the gate the torch button's
    /// visibility checks (TES-84 mirror of the Android `scanner.hasTorch()`). `AVCaptureMrzScanner` (the K/N
    /// scanner) exposes no `hasTorch`/`torch` seam of its own, so this is derived here from the published
    /// ``previewSession``'s bound video device - the same seam ``setTorch(_:)`` already reads. `false` while
    /// no session is live (nothing to check yet).
    var hasTorch: Bool {
        currentTorchDevice()?.hasTorch ?? false
    }

    /// The configuration this presentation runs with, fixed when the model is created (TES-155).
    let config: MrzScannerConfig
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
    /// so it survives the state transitions the collector drives - e.g. a camera-in-use → scanning resume.
    private var decodeRouted = false

    /// Frame-agreement gate over the live decode stream (TES-91 mirror): a decode routes on only once
    /// ``consensusReads`` frames read the SAME document, so a transient OCR misread the MRZ has no check
    /// digit for (e.g. a filler `<` read as a letter in the name field) cannot win on one bad frame. Reset
    /// alongside ``decodeRouted`` whenever a fresh live session begins (``selectMethod(_:)``,
    /// ``rescan()``). Saved-image / manual entry are one-shot and route without this gate. Mirrors the
    /// Android `consensus` (`remember(config.consensusReads) { MrzDecodeConsensus(...) }`).
    // `try!`: the constructor throws only for a threshold below 1 (TES-198), and `consensusReads` is a
    // fixed constant of at least 1.
    private var consensus = try! MrzDecodeConsensus(threshold: ScannerModel.consensusReads)

    /// How many agreeing frames the live consensus gate requires before a reading is confirmed. Hardcoded to
    /// mirror `MrzDecodeConsensus.DEFAULT_THRESHOLD` (mrz-camera-core) - unlike the Android `MrzScannerConfig`,
    /// this iOS `MrzScannerConfig` has no `consensusReads` extension point yet, so there is nothing to plumb a
    /// consumer override through; add one here if/when the config gains that knob.
    private static let consensusReads: Int32 = 2

    /// Wall-clock of the last frame the consensus gate reported as gathering, so the "hold steady" cue lingers
    /// briefly instead of strobing: detection flickers frame-to-frame even on a steady card (a miss between
    /// two decodes is normal), so the cue clears only after ``gatheringCueLinger`` with no decode. Mirrors the
    /// Android `lastDecodeAtMs` / `GATHERING_CUE_LINGER_MS`.
    private var lastGatheringAt: Date?
    private let gatheringCueLinger: TimeInterval = 0.6

    /// TES-103: wall-clock of the last frame that read a document the app does not accept, so the live notice
    /// stays while that document is in view and drops ``notAcceptedNoticeLinger`` after it leaves. Mirrors the
    /// Android `lastNotAcceptedAtMs`.
    private var lastNotAcceptedAt: Date?

    /// The model's clock: behind ``lastNotAcceptedAt`` and ``lastGatheringAt`` and their linger checks. A seam
    /// so a host test can step past a linger without waiting; the screen always uses the wall clock.
    var notAcceptedClock: () -> Date = { Date() }

    /// The kinds of document this presentation accepts (TES-103). Never empty: the config refuses an empty set.
    var acceptedDocumentTypes: Set<DocumentCategory> {
        config.acceptedDocumentTypes
    }

    /// TES-151: whether the configured struggle timeout has already elapsed for this session. If the timer
    /// fires while the scanning state is not showing (a camera-in-use notice, say), the next qualifying frame
    /// flips the UI to struggling the moment scanning resumes (see the `.stayScanning` branch in
    /// ``onCameraResult(_:)``).
    private var struggleTimeoutElapsed = false

    /// Guards ``armStruggleTimeout()`` so it fires once per live session, the first time the preview session
    /// goes live (mirrors the Android `awaitCameraActiveThenTimeout` gate) rather than at scan-intent -
    /// camera-boot time must not count against the struggle budget.
    private var struggleTimeoutArmed = false

    /// TES-93 mirror: the in-progress manual-entry text, hoisted here (survives the flow's lifetime) rather
    /// than living only inside `ScannerState.manualRaw` - which a naive `selectMethod` / `rescan` would
    /// rebuild from scratch (an empty `.manualRaw`), silently discarding whatever the user had typed on a
    /// Manual→other→Manual round trip.
    private var manualDraft = ""

    /// TES-137 mirror of the Android `MANUAL_ENTRY_MAX_CHARS`: a hard ceiling on the manual-entry draft's
    /// length, in characters. A real MRZ is at most 3 lines of 44 characters (132 chars) plus a little
    /// whitespace - 1024 is generously above that so a legitimate typed or pasted MRZ is never truncated,
    /// while an arbitrarily large paste is bounded before it reaches ``manualDraft`` / ``ScannerState``.
    /// Truncated, never rejected (reader, not oracle): a 1024-character draft is already not a readable MRZ
    /// regardless of where the excess came from.
    private static let manualEntryMaxChars = 1024

    // MARK: - Session scan deadline (TES-124/125/126)

    /// The time left for the countdown chip, or `nil` when `config.scanTimeout` is `nil` (no deadline → no
    /// chip). Refreshed on each ~500ms tick while the app is foreground, so the screen republishes twice a
    /// second while a deadline runs (as it re-rendered before, when the root view read this under
    /// Observation). In seconds. Mirrors the Android `rememberScanDeadline`'s returned `Duration?`.
    @Published private(set) var timeRemaining: TimeInterval?

    /// The pure accumulator behind the deadline (see ``DeadlineClock``); `nil` when `config.scanTimeout` is
    /// `nil` - the deadline never arms.
    private var deadlineClock: DeadlineClock?

    /// The monotonic clock the deadline measures active elapsed time against, in seconds - never wall-clock
    /// `Date` (a clock change, DST, or NTP correction must never perturb the deadline). ``monotonicNow()``
    /// reads the same clock `ContinuousClock` does (it keeps counting while the device sleeps) and works on
    /// iOS 15. Mirrors the Android `SystemClock.elapsedRealtime()`.
    private let deadlineTickClock: () -> TimeInterval = monotonicNow

    /// The instant of the deadline's last tick while foreground, so each tick advances by the REAL elapsed
    /// time since then (drift-corrected), not the nominal 500ms interval. Mirrors the Android `lastTick`.
    private var deadlineLastTick: TimeInterval?

    private var deadlineTask: Task<Void, Never>?

    /// Whether the app is currently foreground - the deadline advances only while this is `true`. Defaults to
    /// `true` (the scanner only ever appears while the app is already active); ``setForeground(_:)`` keeps it
    /// current as the scene phase changes.
    private var deadlineForeground = true

    init(config: MrzScannerConfig, onResult: @escaping (TesseraUIResult) -> Void) {
        self.config = config
        self.onResult = onResult
        self.state = initialState(enabledMethods: config.enabledMethods)
    }

    /// The sink the app registered with `TelemetrySinkRegistry` (the no-op sink when none is). Read when each
    /// scanner or reader is built, exactly as the Android screen does through its scanner's default argument,
    /// so `mrz.camera.frame` events reach the app's sink on both platforms (TES-196). Kotlin default arguments
    /// are not visible from Swift, so the lookup has to be spelled out here.
    static func registeredTelemetrySink() -> any TelemetrySink {
        TelemetrySinkRegistry.shared.current
    }

    // MARK: - Lifecycle

    /// Starts the flow for the current initial state. Idempotent per entered method. Called by the root view
    /// on appear.
    func onAppear() {
        applyStateEntry(state)
        beginSession()
    }

    /// Tears the flow down - stops and closes the scanner and cancels the collectors, including the
    /// session-level deadline tick loop. Called on disappear.
    func onDisappear() {
        teardownScanner()
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }


    // DECIDED (TES-129, 2026-07-30): flow state is deliberately NOT persisted across scene/process death —
    // no SceneStorage/Codable snapshot, unlike Android's saved-instance restoration (TES-102). iOS has no
    // config-change recreation (rotation loses nothing; this observable model is the in-memory layer that
    // survives view churn), so the only loss trigger is backgrounding plus memory eviction inside a
    // seconds-long flow — a re-scan costs seconds, and not persisting means the SDK never writes document
    // data of its own. Revisit only on real field reports of lost long manual entries, privacy-first.

    /// Starts the session-level scan-timeout deadline (TES-124) exactly once, independent of which screen or
    /// reading method is showing - called from ``onAppear()``, so it starts the moment the scanner UI appears
    /// and survives every later method switch, review, or manual-entry detour. A `nil` `config.scanTimeout`
    /// never arms (``timeRemaining`` stays `nil`, so the countdown chip never shows - `nil` plays the role the
    /// Android `Duration.INFINITE` does; a non-finite seconds value is treated the same). Idempotent: a
    /// second call (e.g. a re-fired `.onAppear`) is a no-op once a deadline is already running.
    private func beginSession() {
        guard deadlineClock == nil, let timeout = config.scanTimeoutInterval, timeout.isFinite else { return }
        deadlineClock = DeadlineClock(total: timeout)
        timeRemaining = timeout
        armDeadlineTickIfNeeded()
    }

    /// Forwards a scene-phase change from the root view's `@Environment(\.scenePhase)`. The deadline advances
    /// only while foreground - the iOS mirror of the Android session deadline's `Lifecycle.State.RESUMED`
    /// gate (`repeatOnLifecycle`): time spent backgrounded or on the lock screen does not count, and the
    /// deadline resumes from the accumulated elapsed time rather than restarting (TES-126). Camera-interrupted
    /// ("in use") time still counts - that is a foreground state; only backgrounding pauses the clock, since
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
        deadlineLastTick = deadlineTickClock()
        deadlineTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
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
    /// ``timeRemaining`` for the countdown chip, and - the first time the accumulator reaches the total -
    /// ends the flow as `Cancelled(timedOut)` on whatever screen the user is currently on, exactly like the
    /// Android `onElapsed`.
    private func tickDeadline() {
        guard var clock = deadlineClock, let lastTick = deadlineLastTick else { return }
        let now = deadlineTickClock()
        deadlineLastTick = now
        let justFired = clock.advance(by: now - lastTick)
        deadlineClock = clock
        timeRemaining = clock.remaining
        if justFired {
            deadlineTask?.cancel()
            deadlineTask = nil
            onResult(.cancelled(.timedOut))
        }
    }

    // MARK: - VoiceOver announcements (TES-58)
    //
    // A new screen is announced by the root view with a screen-changed notification (TES-298); the
    // announcements here are for overlays and notices that appear on a screen that stays.

    /// Posts a plain-text VoiceOver announcement for a localization `key` directly - used for the
    /// struggling/gathering overlays, a rising-edge flag on `.scanning` rather than a distinct
    /// ``ScannerState`` case, so they are not a screen change. Every
    /// call site guards this to fire once, on the transition into the overlay - never on every recompute of
    /// an already-showing one, mirroring the Android `StrugglingHint`/`GatheringHint` polite live regions.
    private func postAnnouncement(key: String) {
        postAnnouncement(text: TesseraStrings.string(key, bundle: config.stringsBundle))
    }

    /// Posts an already-resolved announcement text - used for the TES-103 not-accepted notice and note, whose
    /// spoken text is built from several keys (``notAcceptedAnnouncement(_:acceptedDocumentTypes:bundle:)``).
    private func postAnnouncement(text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: - Global chrome hooks

    /// The global cancel (the top bar's ✕). Reports WHY the flow ended based on what the user was looking
    /// at when they closed (TES-115, the Android `dismissReasonFor` mirror): the terminal
    /// camera-unavailable screen → ``DismissReason/cameraUnavailable``, either permission screen →
    /// ``DismissReason/permissionDenied``, anything else - including the recoverable in-use notice -
    /// ``DismissReason/userDismissed``. The decision is the pure ``dismissReason(for:)``.
    func cancel() {
        onResult(.cancelled(dismissReason(for: state)))
    }

    /// Whether the manual-entry escape (offered from the struggling hint, both camera-status notices, and the
    /// permission gate) should be shown at all - `false` when the consumer's `enabledMethods` excludes
    /// `.manualEntry`, so a camera-only config never routes the user into a screen they cannot reach any other
    /// way. Mirrors the Android `showManualEntry`.
    var showManualEntry: Bool {
        config.enabledMethods.contains(.manualEntry)
    }

    /// Switching reading method from the switcher: camera → scanning, photo → the await-pick launcher state,
    /// type → manual raw (prefilled from the hoisted ``manualDraft``, TES-93 - a Manual→other→Manual round
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

    /// Rescanning / trying again: returns to whichever method produced the current outcome screen - the iOS
    /// mirror of the Android `returnToSource` (from a review, TES-92/TES-96) and the read-failed
    /// `ReadFailedContent.onTryAgain` (hardcoded to re-open the photo picker, since read-failed is only ever
    /// reached via saved-image - a live-camera parse failure never routes while the consensus gate is waiting
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

    /// Returns to whichever reading method produced a ``ScannerState/review(decoded:expanded:source:)`` -
    /// camera → the live preview, saved-image → re-open the picker, manual → the entry screen, PREFILLED with
    /// the lines that were actually submitted for this review (TES-93 - editing a manual-provenance reading
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
    /// the struggle-timer arm latch) - called whenever a fresh live session begins (``selectMethod(_:)``,
    /// ``rescan()``), mirroring the Android flow's paired resets of `decodeRouted` / `consensus` /
    /// `struggleTimeoutElapsed`.
    private func resetLiveSessionGates() {
        decodeRouted = false
        consensus.reset()
        struggleTimeoutElapsed = false
        struggleTimeoutArmed = false
    }

    /// Enter manual raw entry (the read-failed / struggle escape), prefilled from the hoisted ``manualDraft``.
    func enterManualEntry() {
        transition(to: .manualRaw(text: manualDraft, parseFailed: false))
    }

    /// Bind the in-progress manual text (called on every edit) - mirrored into the hoisted ``manualDraft``
    /// (TES-93) and clears a prior parse-failed note (the input the user is fixing is no longer "failed").
    /// TES-137: truncated to ``manualEntryMaxChars`` before it reaches ``manualDraft`` / ``ScannerState`` -
    /// bounds a large paste at the source, mirroring the Android `MANUAL_ENTRY_MAX_CHARS` cap.
    func updateManualText(_ text: String) {
        let bounded = String(text.prefix(Self.manualEntryMaxChars))
        manualDraft = bounded
        state = .manualRaw(text: bounded, parseFailed: false)
    }

    /// Assemble a `Decoded` from the typed text (pure, host-tested; format auto-detected). A success /
    /// partial-success routes to review (or straight back under instant-return) exactly as a camera decode
    /// does. A parse failure stays HERE with an inline note - the typed text is preserved and there is no jump
    /// to the camera/photo-flavoured read-failed screen. Mirrors the Android manual-entry `onRead`.
    func readManual(text: String) {
        let decoded = assembleManualDecoded(text: text)
        if decoded.parse is ParseResult.Failure {
            state = .manualRaw(text: text, parseFailed: true)
        } else {
            routeThroughDecode(decoded, source: .manualEntry, manualText: text)
        }
    }

    // MARK: - Saved-image reading

    /// Present the system photo picker (the "Choose photo" affordances route here).
    func launchPhotoPicker() {
        photoPickerPresented = true
    }

    /// A photo was picked: show the analyzing state and read it on-device. `load` fetches the picked image's
    /// data (`nil` when it cannot be loaded); each picker path supplies its own (`PhotosPickerItem` on iOS 16+,
    /// `NSItemProvider` below), so the model needs neither type. Mirrors the Android `readPickedImage`.
    func handlePickedImage(load: @escaping @MainActor () async -> Data?) {
        state = .savedImageAnalyzing
        Task { await readPickedPhoto(await load()) }
    }

    /// Reads the picked photo through the `SavedImageMrzReader` in single-read mode, entirely on-device, then
    /// applies the pure ``mapSavedImageResult(_:)``: a single decode → routed exactly as a camera decode;
    /// nothing readable → the empty screen. Single read, like the live camera (TES-86/TES-91) - no tolerant
    /// candidate enumeration and no "choose the reading" screen; if OCR misread an ambiguous glyph, the
    /// review's check-digit observations surface it and the user rescans, the same safety net the camera has.
    /// Saved-image reading is opt-in and off by default - reaching here means the consumer enabled
    /// ``ScanMethod/savedImage``, which IS the acknowledgement (ADR-023), so the acknowledgement is
    /// constructed here with no separate screen.
    private func readPickedPhoto(_ data: Data?) async {
        guard
            let data,
            let url = writeTempImage(data)
        else {
            state = .savedImageEmpty
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
            telemetry: Self.registeredTelemetrySink(),
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
            return
        }
        switch mapSavedImageResult(result) {
        case let .singleDecode(decoded):
            routeThroughDecode(decoded, source: .savedImage)
        case .empty:
            state = .savedImageEmpty
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

    /// Confirm the reviewed decode - hand it back to the host.
    func confirmReview() {
        guard case let .review(decoded, _, _) = state else { return }
        onResult(.confirmed(decoded))
    }

    // MARK: - State transitions

    /// Moves to a new state and runs its entry side effects (start/stop scanner, launch picker, arm the
    /// struggle timer). Centralised so every transition - switcher, rescan, decode routing - goes through the
    /// same entry wiring, mirroring how the Android flow reacts to `uiState` changes.
    /// Assigns ``state`` only when the screen would change (``ScannerState/showsSameScreen(as:)``), and
    /// returns whether it did. `@Published` republishes the whole screen on every assignment, even of an equal
    /// value (as `@Observable` notified on every set before), so a write that can repeat at frame rate goes
    /// through here.
    @discardableResult
    private func updateState(_ newState: ScannerState) -> Bool {
        guard !state.showsSameScreen(as: newState) else { return false }
        state = newState
        return true
    }

    private func transition(to newState: ScannerState) {
        state = newState
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
                watchPermissionWhileUndecided()
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
    /// `showRationale` is always `false`; a decided status (`.denied`/`.restricted`) maps to `hasAsked` so
    /// the pure function yields the permanently-denied face; `.notDetermined` always yields needs-grant.
    private func evaluatePermission() -> PermissionScreenState {
        let status = authorizationStatus()
        return permissionScreenState(
            granted: status == .authorized,
            hasAsked: status != .notDetermined,
            showRationale: false
        )
    }

    /// The permission screen's primary "Continue" action: hand the request to the host (the SDK never
    /// requests a permission itself), then re-read the status. No-op-safe when the host supplied no handler
    /// (the screen hides the button in that case).
    func requestPermission() {
        config.onRequestPermission?()
        // The host's request may already have been answered (a status decided earlier), so re-read now; an
        // undecided status keeps being watched until the person answers the system dialog.
        recheckPermission()
    }

    /// Opens this app's Settings page so the user can turn Camera on after a denial - UI navigation, not a
    /// permission request (within the permission boundary).
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Re-evaluate the permission when the app returns to the foreground, so a grant made via the host's
    /// request OR via the Settings screen takes effect without relaunching. Only acts while a permission face
    /// is showing: a fresh grant resumes scanning.
    func recheckPermissionOnForeground() {
        recheckPermission()
    }

    /// Re-reads the status while a permission face shows and moves on when it is decided: a grant starts the
    /// camera, a denial shows the Settings face. Assigns ``state`` directly, so no transition is skipped.
    private func recheckPermission() {
        switch state {
        case .permissionNeeded, .permissionPermanentlyDenied:
            switch evaluatePermission() {
            case .granted:
                stopPermissionWatch()
                transition(to: .scanning(struggling: false, gathering: false))
            case .needsGrant:
                state = .permissionNeeded
                watchPermissionWhileUndecided()
            case .permanentlyDenied:
                stopPermissionWatch()
                state = .permissionPermanentlyDenied
            }
        default:
            stopPermissionWatch()
        }
    }

    /// While the needs-grant face shows and the status is still undecided, re-reads it every
    /// ``permissionPollInterval`` and moves on the moment the person answers the system dialog. The foreground
    /// re-check alone is not enough: the screen cannot see the host's request finish (the callback returns
    /// nothing), the dialog does not reliably make the scene inactive and active again, and when it does the
    /// status can still read undecided at that moment. Reads only; never requests. Idempotent.
    private func watchPermissionWhileUndecided() {
        guard permissionWatchTask == nil else { return }
        let interval = permissionPollInterval
        permissionWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                guard let self else { return }
                let keepWatching = await MainActor.run { () -> Bool in
                    guard case .permissionNeeded = self.state else {
                        self.permissionWatchTask = nil
                        return false
                    }
                    guard self.authorizationStatus() != .notDetermined else { return true }
                    self.permissionWatchTask = nil
                    self.recheckPermission()
                    return false
                }
                if !keepWatching { return }
            }
        }
    }

    private func stopPermissionWatch() {
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
    }

    // MARK: - Camera wiring

    /// Starts (or keeps running) the live scanner for the scanning state. Constructs the scanner with preview
    /// armed on first use and begins collecting `results` and `previewSession`. The struggle timeout is armed
    /// separately, once the preview actually goes live (see ``deliverPreviewSession(_:)`` - TES-97 item 6),
    /// not here at scan-intent. The session-level scan deadline is NOT armed here either - unlike the old
    /// camera-scoped timer this replaced, it lives at the whole-flow level (``beginSession()``, called once
    /// from ``onAppear()``) and runs independently of whether the camera is even the active method.
    private func startScanningIfNeeded() {
        if let cameraStartOverride {
            cameraStartOverride()
            return
        }
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
            telemetry: Self.registeredTelemetrySink(),
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

    /// After the configured struggle timeout with no decode, marks the timeout elapsed and flips the scanning
    /// state to `struggling` on the timer alone (TES-151: no text has to have been seen, so a covered lens or
    /// an empty wall gets the hint too). The camera keeps running, so a decode arriving later still routes; a
    /// nil timeout means "never struggle", so the timer does not arm. If the scanning state is not showing
    /// when the timer fires, the next frame flips it (see the `.stayScanning` branch in
    /// ``onCameraResult(_:)``). Armed once per live
    /// session the first time the preview goes live (``deliverPreviewSession(_:)``, TES-97 item 6) - not at
    /// scan-intent - so camera-boot time is never counted against the budget. Mirrors the Android struggle
    /// `LaunchedEffect` / `onStruggling`.
    func armStruggleTimeout() {
        struggleTask?.cancel()
        // A nil struggleTimeout means "never struggle".
        guard let timeout = config.struggleTimeoutInterval else { return }
        let nanos = nanoseconds(for: timeout)
        struggleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.struggleTimeoutElapsed = true
                guard case let .scanning(struggling, gathering, notAccepted) = self.state, !struggling else { return }
                self.state = .scanning(struggling: true, gathering: gathering, notAccepted: notAccepted)
                self.postAnnouncement(key: "tessera_scanner_struggling_hint")
            }
        }
    }

    /// Nanoseconds for `Task.sleep`, clamped at ≥0 (and at the largest sleep for a huge or infinite value).
    /// Used by the struggle timer (the session deadline sleeps a fixed 500ms tick instead).
    private func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        let nanos = (seconds * 1_000_000_000).rounded(.down)
        return nanos >= 18_000_000_000_000_000_000 ? .max : UInt64(nanos)
    }

    private func teardownScanner() {
        // The torch turns off when the session stops; reset the flags so a re-start reapplies torchOnByDefault.
        torchOn = false
        torchDefaultApplied = false
        struggleTask?.cancel(); struggleTask = nil
        struggleTimeoutArmed = false
        lastGatheringAt = nil
        lastNotAcceptedAt = nil
        resultsTask?.cancel(); resultsTask = nil
        previewTask?.cancel(); previewTask = nil
        previewSession = nil
        scanner?.stop()
        scanner?.close()
        scanner = nil
        recognizer = nil
    }

    /// Retargets the OCR band to the guide's real on-screen region - called by the viewfinder whenever its
    /// layout resolves or changes, with the guide rect already converted by AVFoundation's own
    /// `metadataOutputRectOfInterest(for:)` (so `metadataRect` is normalized against the unrotated capture
    /// buffer, top-left origin - the recognizer maps it into Vision's space internally). No-op when the
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
    /// crosses from the collect loop wrapped in an ``UnsafeTransfer`` - safe because the collector produces
    /// one value at a time and never touches it again after handing it over (a single-owner transfer).
    private func deliverCameraResult(_ result: UnsafeTransfer<MrzScanResult>) {
        onCameraResult(result.value)
    }

    /// Main-actor delivery of the latest published `AVCaptureSession` (or `nil`), for the preview view.
    private func deliverPreviewSession(_ session: UnsafeTransfer<AVCaptureSession?>) {
        applyPreviewSession(session.value)
    }

    /// The body of ``deliverPreviewSession(_:)``, internal so a host test can publish a session (the simulator
    /// has no camera, so no real one ever arrives).
    func applyPreviewSession(_ session: AVCaptureSession?) {
        previewSession = session
        guard session != nil else { return }
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
        guard let device = currentTorchDevice(), device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            // Torch config can fail transiently (device busy); leave the state unchanged.
        }
    }

    /// Test seam: supplies a stand-in torch device in place of the one reached through the session. `nil` in
    /// production, so the real device is always used.
    var torchDeviceOverride: (() -> (any TorchDevice)?)?

    private func currentTorchDevice() -> (any TorchDevice)? {
        if let torchDeviceOverride { return torchDeviceOverride() }
        return currentCaptureDevice()
    }

    /// The active video capture device, reached from the running session the scanner publishes.
    private func currentCaptureDevice() -> AVCaptureDevice? {
        previewSession?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }?
            .device
    }

    /// The continuous state reducer over the scanner's result stream - the iOS mirror of the Android
    /// `onCameraResult`. Every per-frame result runs through the pure ``reduceCameraResult(_:)`` and the
    /// resulting effect is applied here. Repeated decoded frames are guarded by the ``decodeRouted`` latch
    /// (route only the first). A camera-in-use notice self-resumes: any later non-error result flips the flow
    /// back to scanning, so no retry is needed.
    ///
    /// A decoded frame is a transient bad frame if it did not parse (blurred/garbled OCR) - live camera keeps
    /// scanning and waits for a clean frame rather than committing to read-failed on one bad read (TES-86); a
    /// parseable frame is offered to the consensus gate (``consensus``) rather than routed on sight, so a
    /// transient misread the MRZ has no check digit for cannot win on one frame - Gathering keeps scanning
    /// (surfacing the "hold steady" cue), Confirmed routes once (the latch stops repeats). Mirrors the Android
    /// `onCameraResult`'s consensus wiring (TES-91).
    ///
    /// Internal, not private, so a host test can feed it frames without a camera (TES-103).
    func onCameraResult(_ result: MrzScanResult) {
        switch reduceCameraResult(result) {
        case let .goDecoded(decoded):
            // TES-103: the pure stepLiveDecode also applies the app's intake rule. A reading the frames agree
            // on but the app does not accept never trips the latch and never counts as the confirmed reading:
            // the consensus is reset, the preview shows a notice, and the session keeps scanning, so a later
            // document of an accepted kind still routes. With every kind accepted (the default) it behaves
            // exactly as before.
            switch stepLiveDecode(
                decoded,
                alreadyRouted: decodeRouted,
                consensus: consensus,
                acceptedDocumentTypes: acceptedDocumentTypes
            ) {
            case .ignore:
                return
            case let .route(decoded):
                decodeRouted = true
                // TES-134 (Android hapticFeedback mirror): bump the sensory-feedback trigger the moment a
                // live-camera read is accepted — the view's `.sensoryFeedback` plays the confirm haptic
                // (gated there on `config.hapticFeedback`). Camera path only, exactly like Android.
                confirmedReadHaptic += 1
                routeThroughDecode(decoded, source: .camera)
            case .gathering:
                lastGatheringAt = notAcceptedClock()
                // A new reading gathering also replaces a not-accepted notice (TES-103).
                if case let .scanning(struggling, gathering, notAccepted) = state, !gathering || notAccepted != nil {
                    state = .scanning(struggling: struggling, gathering: true, notAccepted: nil)
                    if !gathering {
                        postAnnouncement(key: "tessera_scanner_gathering_hint")
                    }
                }
            case .notAcceptedGathering:
                // TES-103: a not-accepted document is still in view. No "hold steady" cue (it is not heading
                // for review); only keep the notice alive while it shows.
                lastNotAcceptedAt = notAcceptedClock()
            case let .notAccepted(read):
                lastNotAcceptedAt = notAcceptedClock()
                showLiveNotAcceptedNotice(read)
            }
        case .goCameraInUse:
            // Can arrive on every frame while another app holds the camera: publish only the first, so the
            // screen is not rebuilt at frame rate.
            updateState(.cameraInUse)
        case .goCameraUnavailable:
            updateState(.cameraUnavailable)
        case .stayScanning:
            // A transient miss. If a recoverable camera-in-use notice is showing, a clean frame proves the
            // camera reconnected — return to scanning.
            if case .cameraInUse = state {
                state = .scanning(struggling: false, gathering: false)
                return
            }
            guard case let .scanning(struggling, gathering, notAccepted) = state else { return }
            var newStruggling = struggling
            var newGathering = gathering
            var newNotAccepted = notAccepted
            // Clear the "hold steady" cue only after the linger window with no decode, so a single miss
            // between two decodes (normal even on a steady card) does not strobe it.
            if newGathering, let lastGathering = lastGatheringAt,
               notAcceptedClock().timeIntervalSince(lastGathering) > gatheringCueLinger {
                newGathering = false
            }
            // TES-151: the struggle timeout already elapsed while scanning was not showing — this frame, on
            // return to scanning, flips the UI to struggling.
            if !newStruggling, struggleTimeoutElapsed {
                newStruggling = true
            }
            // TES-103: the not-accepted notice drops a while after that document left the view, so the framing
            // guide (or the struggling hint) comes back.
            if newNotAccepted != nil, let lastNotAccepted = lastNotAcceptedAt,
               notAcceptedClock().timeIntervalSince(lastNotAccepted) > notAcceptedNoticeLinger {
                newNotAccepted = nil
            }
            if newStruggling != struggling || newGathering != gathering || newNotAccepted != notAccepted {
                state = .scanning(struggling: newStruggling, gathering: newGathering, notAccepted: newNotAccepted)
                // Announce only the rising edge (false → true), never the falling edge or an unrelated change.
                if newStruggling, !struggling {
                    postAnnouncement(key: "tessera_scanner_struggling_hint")
                }
            }
        }
    }

    /// Routes a decode to the matching state via ``routeDecode(_:reviewMode:acceptedDocumentTypes:)`` - shared
    /// by the camera path, manual entry, and saved-image, all of which produce a `Decoded` that follows the
    /// identical routing. `source` is carried onto ``ScannerState/review(decoded:expanded:source:)`` so a
    /// rescan/edit-entry returns to the method that produced it (TES-92/TES-93/TES-96). Mirrors the Android
    /// `routeDecoded` / `routeThroughDecode`.
    ///
    /// TES-103: a reading of a kind the app does not accept is never reviewed or returned; each method states
    /// it in its own place (``notAcceptedState(for:read:current:manualDraft:)``). `manualText` is the typed
    /// text to keep on the entry screen; the camera filters before it gets here (``stepLiveDecode(_:alreadyRouted:consensus:acceptedDocumentTypes:)``),
    /// so the camera branch is only a fallback.
    private func routeThroughDecode(_ decoded: MrzScanResultDecoded, source: ScanMethod, manualText: String? = nil) {
        switch routeDecode(decoded, reviewMode: config.reviewMode, acceptedDocumentTypes: acceptedDocumentTypes) {
        case let .showReadFailed(capturedText):
            transition(to: .readFailed(capturedText: capturedText))
        case let .returnConfirmed(decoded):
            onResult(.confirmed(decoded))
        case let .showReview(decoded):
            transition(to: .review(decoded: decoded, expanded: false, source: source))
        case let .notAccepted(read):
            switch source {
            case .camera:
                showLiveNotAcceptedNotice(read)
            case .savedImage:
                // The title is announced on arrival (announcementKey), like the "no MRZ found" screen.
                transition(to: notAcceptedState(for: .savedImage, read: read, current: state, manualDraft: manualDraft))
            case .manualEntry:
                if let manualText { manualDraft = manualText }
                // Stays on the entry screen: plain assignment, no transition (the screen does not change).
                state = notAcceptedState(for: .manualEntry, read: read, current: state, manualDraft: manualDraft)
                postAnnouncement(text: notAcceptedAnnouncement(
                    read, acceptedDocumentTypes: acceptedDocumentTypes, bundle: config.stringsBundle))
            }
        }
    }

    /// Shows the live not-accepted notice for `read` over the preview (TES-103), announcing it when it first
    /// appears or names a different kind.
    private func showLiveNotAcceptedNotice(_ read: NotAcceptedKind) {
        let previous: NotAcceptedKind?
        if case let .scanning(_, _, notAccepted) = state { previous = notAccepted } else { return }
        // Called on every frame the not-accepted document stays in view: an unchanged notice is not republished.
        updateState(showNotAcceptedNotice(state, read: read))
        if previous != read {
            postAnnouncement(text: notAcceptedAnnouncement(
                read, acceptedDocumentTypes: acceptedDocumentTypes, bundle: config.stringsBundle))
        }
    }
}

// MARK: - Flow collection bridging

/// A single-owner transfer box for moving a non-Sendable value across an isolation boundary when the value is
/// produced, handed over, and never touched again by the sender (the K/N collect loop yields one value at a
/// time). `@unchecked Sendable` because that ownership discipline - not the type - makes the move safe.
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

/// The part of a camera device the torch switch uses. `AVCaptureDevice` conforms; a host test supplies a fake.
protocol TorchDevice: AnyObject {
    var hasTorch: Bool { get }
    var isTorchAvailable: Bool { get }
    var torchMode: AVCaptureDevice.TorchMode { get set }
    func lockForConfiguration() throws
    func unlockForConfiguration()
}

extension AVCaptureDevice: TorchDevice {}

/// The torch button's symbol: the filled bolt while the torch is on, the slashed bolt while it is off.
func torchIconName(on: Bool) -> String {
    on ? "bolt.fill" : "bolt.slash.fill"
}
