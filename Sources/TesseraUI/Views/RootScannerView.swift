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
        case let .scanning(struggling):
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
                    if struggling {
                        StrugglingHint(onManualEntry: { model.enterManualEntry() })
                    }
                }

        case .permissionNeeded:
            PermissionScreen(
                state: .needsGrant,
                onGrant: { model.requestPermission() },
                onOpenSettings: { model.openSettings() },
                onManualEntry: { model.enterManualEntry() },
                hasRequestHandler: config.onRequestPermission != nil
            )

        case .permissionPermanentlyDenied:
            PermissionScreen(
                state: .permanentlyDenied,
                onGrant: { model.requestPermission() },
                onOpenSettings: { model.openSettings() },
                onManualEntry: { model.enterManualEntry() },
                hasRequestHandler: config.onRequestPermission != nil
            )

        case .cameraInUse:
            CameraInUseScreen(onManualEntry: { model.enterManualEntry() })

        case .cameraUnavailable:
            CameraUnavailableScreen(onManualEntry: { model.enterManualEntry() })

        case let .review(decoded, expanded):
            ReviewScreen(
                decoded: decoded,
                expanded: expanded,
                onToggleExpanded: { model.toggleReviewExpanded() },
                onUse: { model.confirmReview() },
                onRescan: { model.rescan() }
            )

        case let .readFailed(capturedText):
            ReadFailedScreen(
                capturedText: capturedText,
                onTryAgain: { model.rescan() },
                onManualEntry: { model.enterManualEntry() }
            )

        case .awaitingSavedImagePick:
            AwaitingSavedImagePickScreen(onChoosePhoto: { model.launchPhotoPicker() })

        case .savedImageAnalyzing:
            SavedImageAnalyzingScreen()

        case let .savedImageCandidates(candidates):
            SavedImageCandidatesScreen(
                candidates: candidates,
                onPick: { model.pickCandidate($0) },
                onChooseDifferent: { model.launchPhotoPicker() }
            )

        case .savedImageEmpty:
            SavedImageEmptyScreen(
                onChooseDifferent: { model.launchPhotoPicker() },
                onManualEntry: { model.enterManualEntry() }
            )

        case let .manualRaw(text):
            ManualEntryScreen(
                text: text,
                onTextChange: { model.updateManualText($0) },
                onRead: { hint in model.readManual(text: text, hint: hint) },
                onBack: { model.cancel() }
            )

        case .manualFields:
            // Field-by-field manual entry (mockup 06b) is deferred beyond 0.5.0 (TES-79). This state is never
            // produced by the flow; guarded defensively so the switch stays exhaustive.
            EmptyView()
        }
    }
}
