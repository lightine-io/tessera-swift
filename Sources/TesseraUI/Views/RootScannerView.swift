import PhotosUI
import SwiftUI

/// The per-state screen dispatch - the iOS mirror of the Android `ScannerBody`. An exhaustive `switch` over
/// ``ScannerState``, rendered inside the ``ScannerScaffold`` (so the shared top bar + method switcher sit
/// above it). Each leaf screen is its own SwiftUI view; this view owns the ``ScannerModel`` and routes its
/// callbacks. The saved-image photo picker and the foreground permission re-check are attached here (they
/// are host-side platform I/O the model drives).
struct RootScannerView: View {
    @StateObject private var model: ScannerModel
    @Environment(\.scenePhase) private var scenePhase

    // The configuration is fixed per presentation (TES-155): SwiftUI keeps the first model for as long as this
    // view keeps its identity and ignores the `config` of a later init, so every read below goes through the
    // model. Reading the latest `config` here instead would mix two configurations on one open screen (the
    // switcher from the new one, the flow from the old one). A new presentation is a new identity, so it gets a
    // new model with the config it opens with. `StateObject` builds the model only once per identity (the
    // autoclosure is not called again on a later init).
    init(config: MrzScannerConfig, onResult: @escaping (TesseraUIResult) -> Void) {
        _model = StateObject(wrappedValue: ScannerModel(config: config, onResult: onResult))
    }

    /// The configuration this presentation opened with.
    private var config: MrzScannerConfig { model.config }

    @Environment(\.scannerRenderProbe) private var renderProbe

    var body: some View {
        let _ = renderProbe?.report(ScannerRender(switcherMethods: config.enabledMethods, model: model))
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
        // camera read. `.sensoryFeedback` honours the system haptic setting; `enabled` is the consumer's
        // opt-out. Camera path only — manual/saved-image have their own interaction feedback. Gathering (the
        // gate has seen a reading and waits for agreement) means a confirm is likely within a second.
        .compatSuccessHaptic(
            trigger: model.confirmedReadHaptic,
            enabled: config.hapticFeedback,
            likelySoon: isGathering
        )
        // The saved-image photo picker: images only, one photo. A cancel leaves the current screen as is.
        .compatSavedImagePicker(
            isPresented: $model.photoPickerPresented,
            onPick: { model.handlePickedImage(load: $0) }
        )
        // VoiceOver: a new screen is announced when it arrives (TES-298). Keyed on the screen, so an overlay or a
        // toggle on the same screen (struggling hint, expanded review) does not re-announce.
        .compatOnChange(of: screen(of: model.state)) { _ in
            let title = screenTitleKey(for: model.state).map {
                TesseraStrings.string($0, bundle: config.stringsBundle)
            }
            postScreenChanged(title: title)
        }
        .compatOnChange(of: scenePhase) { phase in
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
        // The strings-bundle override (TES-139), injected once so every screen's
        // ``TesseraStrings/string(_:bundle:)`` call sees it. From the model, like the rest of the config.
        .environment(\.tesseraStringsBundle, config.stringsBundle)
    }

    /// Whether the live consensus gate is gathering agreement, so a confirmed read (and its haptic) is near.
    private var isGathering: Bool {
        if case .scanning(_, true, _) = model.state { return true }
        return false
    }

    @ViewBuilder
    private func body(for state: ScannerState) -> some View {
        switch state {
        case let .scanning(struggling, gathering, notAccepted):
            // The single live-preview guidance region (gathering > struggling > the plain framing hint) now
            // renders INSIDE CameraPreviewView's MrzGuideOverlay, below the guide box — not as separate top
            // banners here, so exactly one guidance message ever shows, in one place, over the dimmed scrim.
            CameraPreviewView(
                session: model.previewSession,
                gathering: gathering,
                struggling: struggling,
                notAccepted: notAccepted,
                acceptedDocumentTypes: model.acceptedDocumentTypes,
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
                        Image(systemName: model.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .padding(16)
                    .scannerControl(.torch, bundle: config.stringsBundle)
                    .accessibilityValue(torchAccessibilityValue(on: model.torchOn, bundle: config.stringsBundle))
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

        case let .savedImageNotAccepted(read):
            SavedImageNotAcceptedScreen(
                read: read,
                acceptedDocumentTypes: model.acceptedDocumentTypes,
                onChooseDifferent: { model.launchPhotoPicker() },
                onManualEntry: { model.enterManualEntry() },
                showManualEntry: model.showManualEntry
            )

        case let .manualRaw(text, parseFailed, notAccepted):
            ManualEntryScreen(
                text: text,
                parseFailed: parseFailed,
                notAccepted: notAccepted,
                acceptedDocumentTypes: model.acceptedDocumentTypes,
                onTextChange: { model.updateManualText($0) },
                onRead: { model.readManual(text: text) }
            )
        }
    }
}

// MARK: - Saved-image photo picker

/// Loads the picked image's data; `nil` when it cannot be loaded. Handed to
/// ``ScannerModel/handlePickedImage(load:)``.
typealias PickedImageLoader = @MainActor () async -> Data?

/// Presents SwiftUI's photo picker while `isPresented` is true: images only, a single photo. A pick hands a
/// loader to `onPick` (the selection is held here, not in the model); a cancel only dismisses. Below iOS 16
/// ``View/compatSavedImagePicker(isPresented:onPick:)`` presents a `PHPickerViewController` instead.
@available(iOS 16, *)
struct SavedImagePhotosPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (@escaping PickedImageLoader) -> Void
    @State private var pickedItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $pickedItem, matching: .images)
            .compatOnChange(of: pickedItem) { item in
                guard let item else { return }
                pickedItem = nil
                onPick { try? await item.loadTransferable(type: Data.self) }
            }
    }
}

/// What one render of ``RootScannerView`` used, reported to ``EnvironmentValues/scannerRenderProbe``. Test-only.
struct ScannerRender {
    /// The methods handed to the switcher.
    let switcherMethods: Set<ScanMethod>
    /// The model of this presentation.
    let model: ScannerModel
}

/// A host-test seam: told about each render of ``RootScannerView`` with the configuration it rendered with.
/// A class, so the environment compares it by identity and a test creates it once.
@MainActor
final class ScannerRenderProbe {
    let report: (ScannerRender) -> Void
    init(_ report: @escaping (ScannerRender) -> Void) { self.report = report }
}

extension EnvironmentValues {
    /// The render probe; `nil` (the default) outside tests.
    @Entry var scannerRenderProbe: ScannerRenderProbe? = nil
}
