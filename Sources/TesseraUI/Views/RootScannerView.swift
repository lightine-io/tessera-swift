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
            onSelectMethod: { model.selectMethod($0) }
        ) {
            body(for: model.state)
        }
        .scannerTheme(config.theme)
        .photosPicker(
            isPresented: $model.photoPickerPresented,
            selection: $model.pickedItem,
            matching: .images
        )
        .onChange(of: model.pickedItem) { _, item in
            if let item { model.handlePickedItem(item) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.recheckPermissionOnForeground() }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .accessibilityIdentifier("tessera-mrz-scanner-root")
    }

    @ViewBuilder
    private func body(for state: ScannerState) -> some View {
        switch state {
        case let .scanning(struggling, gathering):
            CameraPreviewView(session: model.previewSession)
                .overlay(alignment: .topTrailing) {
                    if config.showTorchButton {
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
                        .accessibilityIdentifier("tessera-mrz-torch")
                    }
                }
                .overlay(alignment: .top) {
                    // The consensus "hold steady" cue takes render precedence over the struggling hint,
                    // mirroring the Android `MrzGuideOverlay` — a decode in progress is better news than
                    // "still looking", and the struggle latch stays armed underneath.
                    if gathering {
                        Text(String(localized: "tessera_scanner_gathering_hint", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 24)
                            .accessibilityIdentifier("tessera-mrz-gathering")
                    } else if struggling {
                        StrugglingHint(
                            onManualEntry: { model.enterManualEntry() },
                            showManualEntry: model.showManualEntry
                        )
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
                onRead: { model.readManual(text: text) },
                onBack: { model.cancel() }
            )

        case .manualFields:
            // Field-by-field manual entry (mockup 06b) is deferred beyond 0.5.0 (TES-79). This state is never
            // produced by the flow; guarded defensively so the switch stays exhaustive.
            EmptyView()
        }
    }
}
