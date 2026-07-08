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
/// struggle timeout, and the method / rescan / manual-read hooks.
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

    /// Whether the torch is currently on (reflected by the torch button). K/N does not expose the AVFoundation
    /// torch API, so the torch is driven here in Swift via the capture device published on the session.
    private(set) var torchOn = false
    // Applies `torchOnByDefault` once per session, so it is not re-forced on every preview-session update.
    private var torchDefaultApplied = false

    private let config: MrzScannerConfig
    private let onResult: (TesseraUIResult) -> Void

    /// The live scanner, created lazily when the camera path first runs (so a camera-disabled config never
    /// touches AVFoundation). `enablePreview()` is armed at construction, before `start()`.
    private var scanner: AVCaptureMrzScanner?
    private var resultsTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var struggleTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?

    /// A one-shot latch: once a decode has routed on (to review / read-failed / straight back), later decoded
    /// frames from the still-running stream must not re-fire. Kept as model state (not inside the collector)
    /// so it survives the state transitions the collector drives — e.g. a camera-in-use → scanning resume.
    private var decodeRouted = false

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
    }

    /// Tears the flow down — stops and closes the scanner and cancels the collectors. Called on disappear.
    func onDisappear() {
        teardownScanner()
    }

    // MARK: - Global chrome hooks

    /// The global cancel (the top bar's ✕). Reports `Cancelled(userDismissed)`.
    func cancel() {
        onResult(.cancelled(.userDismissed))
    }

    /// Switching reading method from the switcher: camera → scanning, photo → the await-pick launcher state,
    /// type → manual raw. Re-arms the decode latch so a fresh method's first decode routes on. Mirrors the
    /// Android `onSelectMethod`.
    func selectMethod(_ method: ScanMethod) {
        decodeRouted = false
        switch method {
        case .camera:
            transition(to: .scanning(struggling: false))
        case .savedImage:
            transition(to: .awaitingSavedImagePick)
        case .manualEntry:
            transition(to: .manualRaw(text: ""))
        }
    }

    // MARK: - Per-screen hooks

    /// Rescanning / trying again arms the flow for a fresh decode: clear the one-shot latch so the next
    /// decoded frame routes on rather than being swallowed as a repeat, then return to scanning.
    func rescan() {
        decodeRouted = false
        transition(to: .scanning(struggling: false))
    }

    /// Enter manual raw entry (the read-failed / struggle escape).
    func enterManualEntry() {
        transition(to: .manualRaw(text: ""))
    }

    /// Bind the in-progress manual text (called on every edit).
    func updateManualText(_ text: String) {
        state = .manualRaw(text: text)
    }

    /// Assemble a `Decoded` from the typed text and route it exactly as a camera decode — a parse failure
    /// shows the read-failed screen, a success / partial-success goes to review (or straight back under
    /// instant-return). Mirrors the Android manual-entry `onRead`.
    func readManual(text: String, hint: ManualFormatHint) {
        routeThroughDecode(assembleManualDecoded(text: text, hint: hint))
    }

    /// The user chose a saved-image candidate: wrap it into a `Decoded` and route it exactly as any decode —
    /// its own parse verdict carried through, no SDK judgement (the user decided). Mirrors the Android
    /// candidate `onPick`.
    func pickCandidate(_ candidate: MrzCandidate) {
        routeThroughDecode(candidateDecoded(candidate))
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
        Task { await readPickedPhoto(item) }
    }

    /// Reads the picked photo through the tolerant `SavedImageMrzReader`, entirely on-device, then applies the
    /// pure ``mapSavedImageResult(_:)``: candidates → the candidates screen (never picking one); a single
    /// decode → routed exactly as a camera decode; nothing readable → the empty screen. Saved-image reading is
    /// opt-in and off by default — reaching here means the consumer enabled ``ScanMethod/savedImage``, which
    /// IS the acknowledgement (ADR-023), so the acknowledgement is constructed here with no separate screen.
    private func readPickedPhoto(_ item: PhotosPickerItem) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
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
            mode: ParsingMode.strict,
            tolerant: true,
            metadataReader: nil,
            metadataPolicy: CaptureMetadataPolicy.none,
            telemetry: NoOpTelemetrySink(),
            referenceTimeProvider: { nowInstant() }
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

        // Arm the decode latch afresh so a candidate / single-decode route fires.
        decodeRouted = false
        guard let result else {
            state = .savedImageEmpty
            return
        }
        switch mapSavedImageResult(result) {
        case let .candidates(candidates):
            state = .savedImageCandidates(candidates: candidates)
        case let .singleDecode(decoded):
            routeThroughDecode(decoded)
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
        guard case let .review(decoded, expanded) = state else { return }
        state = .review(decoded: decoded, expanded: !expanded)
    }

    /// Confirm the reviewed decode — hand it back to the host.
    func confirmReview() {
        guard case let .review(decoded, _) = state else { return }
        onResult(.confirmed(decoded))
    }

    // MARK: - State transitions

    /// Moves to a new state and runs its entry side effects (start/stop scanner, launch picker, arm the
    /// struggle timer). Centralised so every transition — switcher, rescan, decode routing — goes through the
    /// same entry wiring, mirroring how the Android flow reacts to `uiState` changes.
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
                transition(to: .scanning(struggling: false))
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
    /// armed on first use, begins collecting `results` and `previewSession`, and arms the struggle timeout.
    private func startScanningIfNeeded() {
        if scanner != nil { return }

        // TODO(screen): the camera-permission gate (permissionScreenState over the read-only AVFoundation
        // authorization signals + config.onRequestPermission) lands with the permission-screen slice. The
        // scanner surfaces CaptureError(PermissionDenied) on the stream in the meantime; reduceCameraResult
        // keeps it scanning (the gate governs the permission path once wired).
        let scanner = AVCaptureMrzScanner(
            recognizer: VisionMrzTextRecognizer(),
            mode: ParsingMode.strict,
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

        armStruggleTimeout()
        armScanTimeout()
        scanner.start()
    }

    /// After the configured struggle timeout with no decode, flip the scanning state to `struggling`. The
    /// camera keeps running, so a decode arriving later still routes; a non-finite timeout means "never
    /// struggle", so the timer does not arm. Mirrors the Android struggle `LaunchedEffect`.
    private func armStruggleTimeout() {
        struggleTask?.cancel()
        // A nil struggleTimeout means "never struggle".
        guard let timeout = config.struggleTimeout else { return }
        let nanos = nanoseconds(for: timeout)
        struggleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .scanning = self.state else { return }
                self.state = .scanning(struggling: true)
            }
        }
    }

    /// After the configured scan timeout with no confirmed reading, give up and end the flow as
    /// `Cancelled(timedOut)` — the whole-scan *deadline* (TES-85), distinct from the struggle timer, which only
    /// nudges. A `nil` scanTimeout (the default) never arms. Runs once per scanning session — a rescan
    /// re-creates the scanner and re-arms it — mirroring the Android scan-timeout `LaunchedEffect`.
    private func armScanTimeout() {
        scanTimeoutTask?.cancel()
        guard let timeout = config.scanTimeout else { return }
        let nanos = nanoseconds(for: timeout)
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Only give up if still scanning — a decode that already routed to review/read-failed, or a
                // teardown, leaves this a no-op (the task is cancelled on teardown regardless).
                guard let self, case .scanning = self.state else { return }
                self.onResult(.cancelled(.timedOut))
            }
        }
    }

    /// Nanoseconds for `Task.sleep`, clamped at ≥0. Shared by both timeout timers so they convert identically.
    private func nanoseconds(for duration: Duration) -> UInt64 {
        UInt64(max(0, duration.components.seconds)) * 1_000_000_000
            + UInt64(max(0, duration.components.attoseconds / 1_000_000_000))
    }

    private func teardownScanner() {
        // The torch turns off when the session stops; reset the flags so a re-start reapplies torchOnByDefault.
        torchOn = false
        torchDefaultApplied = false
        struggleTask?.cancel(); struggleTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        resultsTask?.cancel(); resultsTask = nil
        previewTask?.cancel(); previewTask = nil
        previewSession = nil
        scanner?.stop()
        scanner?.close()
        scanner = nil
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
        // Honour torchOnByDefault the first time the camera opens (the device is now reachable via the session).
        if session.value != nil, config.torchOnByDefault, !torchDefaultApplied {
            torchDefaultApplied = true
            setTorch(true)
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
    private func onCameraResult(_ result: MrzScanResult) {
        switch reduceCameraResult(result) {
        case let .goDecoded(decoded):
            if !decodeRouted {
                decodeRouted = true
                routeThroughDecode(decoded)
            }
        case .goCameraInUse:
            state = .cameraInUse
        case .goCameraUnavailable:
            state = .cameraUnavailable
        case .stayScanning:
            // A transient miss. If a recoverable camera-in-use notice is showing, a clean frame proves the
            // camera reconnected — return to scanning.
            if case .cameraInUse = state {
                state = .scanning(struggling: false)
            }
        }
    }

    /// Routes a decode to the matching state via ``routeDecode(_:reviewMode:)`` — shared by the camera path,
    /// manual entry, and candidate pick, all of which produce a `Decoded` that follows the identical routing.
    /// Mirrors the Android `routeDecoded` / `routeThroughDecode`.
    private func routeThroughDecode(_ decoded: MrzScanResultDecoded) {
        switch routeDecode(decoded, reviewMode: config.reviewMode) {
        case let .showReadFailed(capturedText):
            transition(to: .readFailed(capturedText: capturedText))
        case let .returnConfirmed(decoded):
            onResult(.confirmed(decoded))
        case let .showReview(decoded):
            transition(to: .review(decoded: decoded, expanded: false))
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
