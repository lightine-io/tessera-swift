import PhotosUI
import SwiftUI

/// The per-state screen dispatch — the iOS mirror of the Android `ScannerBody`. An exhaustive `switch` over
/// ``ScannerState``, rendered inside the ``ScannerScaffold`` (so the shared top bar + method switcher sit
/// above it). Each leaf screen is its own SwiftUI view; this view owns the ``ScannerModel`` and routes its
/// callbacks. The saved-image photo picker and the foreground permission re-check are attached here (they
/// are host-side platform I/O the model drives).
struct RootScannerView: View {
    @State private var model: ScannerModel
    @Environment(\.scenePhase) private var scenePhase

    init(config: MrzScannerConfig, onResult: @escaping (TesseraUIResult) -> Void) {
        _model = State(initialValue: ScannerModel(config: config, onResult: onResult))
        self.config = config
    }

    private let config: MrzScannerConfig

    var body: some View {
        @Bindable var model = model
        ScannerScaffold(
            enabledMethods: config.enabledMethods,
            currentState: model.state,
            onClose: { model.cancel() },
            onSelectMethod: { model.selectMethod($0) },
            timeRemaining: model.timeRemaining
        ) {
            body(for: model.state)
        }
        .scannerTheme(config.theme)
        // A short confirming haptic the moment a live-camera read is accepted (TES-134, Android
        // `hapticFeedback` mirror): the model bumps the trigger exactly when the consensus gate confirms a
        // camera read. `.sensoryFeedback` honours the system haptic setting; the closure gates the
        // consumer's opt-out (`nil` = no feedback). Camera path only — manual/saved-image have their own
        // interaction feedback.
        .sensoryFeedback(trigger: model.confirmedReadHaptic) { _, _ in
            config.hapticFeedback ? .success : nil
        }
        .photosPicker(
            isPresented: $model.photoPickerPresented,
            selection: $model.pickedItem,
            matching: .images
        )
        .onChange(of: model.pickedItem) { _, item in
            if let item { model.handlePickedItem(item) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Forwards to the session-level scan deadline (TES-124/126) — it advances only while `.active`,
            // pausing on background/inactive and resuming from the accumulated elapsed time, never restarting.
            model.setForeground(phase == .active)
            if phase == .active { model.recheckPermissionOnForeground() }
        }
        .onAppear {
            model.setForeground(scenePhase == .active)
            model.onAppear()
        }
        .onDisappear { model.onDisappear() }
        .accessibilityIdentifier("tessera-mrz-scanner-root")
    }

    @ViewBuilder
    private func body(for state: ScannerState) -> some View {
        switch state {
        case let .scanning(struggling, gathering):
            // The single live-preview guidance region (gathering > struggling > the plain framing hint) now
            // renders INSIDE CameraPreviewView's MrzGuideOverlay, below the guide box — not as separate top
            // banners here, so exactly one guidance message ever shows, in one place, over the dimmed scrim.
            CameraPreviewView(
                session: model.previewSession,
                gathering: gathering,
                struggling: struggling,
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry,
                // WYSIWYG band alignment (TES-129): the viewfinder reports the guide box's real on-screen
                // region (already converted to metadata-output space) and the model retargets Vision's OCR
                // band to it — the iOS mirror of Android's ViewPort alignment.
                onMetadataGuideRegion: { model.updateMrzGuideRegion(metadataRect: $0) }
            )
            .overlay(alignment: .topTrailing) {
                // Shown only when the consumer left the torch enabled AND the bound camera actually has a
                // flash unit (TES-84 mirror) — a device with no flash never gets a dead-looking toggle.
                if config.showTorchButton && model.hasTorch {
                    Button { model.toggleTorch() } label: {
                        Image(systemName: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .padding(16)
                    .accessibilityLabel(String(localized: "tessera_scanner_torch", bundle: .module))
                    .accessibilityAddTraits(model.torchOn ? .isSelected : [])
                    .accessibilityValue(
                        model.torchOn
                            ? String(localized: "tessera_scanner_torch_state_on", bundle: .module)
                            : String(localized: "tessera_scanner_torch_state_off", bundle: .module)
                    )
                    .accessibilityIdentifier("tessera-mrz-torch")
                }
            }

        case .permissionNeeded:
            PermissionScreen(
                state: .needsGrant,
                onGrant: { model.requestPermission() },
                onOpenSettings: { model.openSettings() },
                onManualEntry: { model.enterManualEntry() },
                hasRequestHandler: config.onRequestPermission != nil,
                showManualEntry: model.showManualEntry
            )

        case .permissionPermanentlyDenied:
            PermissionScreen(
                state: .permanentlyDenied,
                onGrant: { model.requestPermission() },
                onOpenSettings: { model.openSettings() },
                onManualEntry: { model.enterManualEntry() },
                hasRequestHandler: config.onRequestPermission != nil,
                showManualEntry: model.showManualEntry
            )

        case .cameraInUse:
            CameraInUseScreen(
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry
            )

        case .cameraUnavailable:
            CameraUnavailableScreen(
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry
            )

        case let .review(decoded, expanded, source):
            ReviewScreen(
                decoded: decoded,
                expanded: expanded,
                source: source,
                onToggleExpanded: { model.toggleReviewExpanded() },
                onUse: { model.confirmReview() },
                onRescan: { model.rescan() }
            )

        case let .readFailed(capturedText):
            ReadFailedScreen(
                capturedText: capturedText,
                onTryAgain: { model.rescan() },
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry
            )

        case .awaitingSavedImagePick:
            AwaitingSavedImagePickScreen(onChoosePhoto: { model.launchPhotoPicker() })

        case .savedImageAnalyzing:
            SavedImageAnalyzingScreen()

        // No candidates state: saved-image reading runs a single strict decode (TES-86/TES-91), so a picked
        // photo either decodes (routes like a camera decode) or reads as empty.

        case .savedImageEmpty:
            SavedImageEmptyScreen(
                onChooseDifferent: { model.launchPhotoPicker() },
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry
            )

        case let .manualRaw(text, parseFailed):
            ManualEntryScreen(
                text: text,
                parseFailed: parseFailed,
                onTextChange: { model.updateManualText($0) },
                onRead: { model.readManual(text: text) }
            )
        }
    }
}
